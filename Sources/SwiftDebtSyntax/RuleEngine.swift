import SwiftDebtCore
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public enum RuleEngineError: Error, Equatable, Sendable, CustomStringConvertible {
    case noRulesSelected
    case duplicateRuleIdentity(RuleIdentity)
    case duplicateSourcePath(SourcePath)

    public var description: String {
        switch self {
        case .noRulesSelected:
            "At least one debt rule must be selected."
        case .duplicateRuleIdentity(let identity):
            "Duplicate rule identity: \(identity)"
        case .duplicateSourcePath(let sourcePath):
            "Duplicate normalized source path: \(sourcePath)"
        }
    }
}

public struct RuleEngine {
    public init() {}

    public func analyze<Rule: DebtRule>(
        _ sources: [SourceUnit],
        using rule: Rule
    ) throws -> AnalysisSnapshot {
        try analyze(sources, using: [rule as any DebtRule])
    }

    public func analyze(
        _ sources: [SourceUnit],
        using rules: [any DebtRule]
    ) throws -> AnalysisSnapshot {
        let registeredRules = try register(rules)
        let selectedSources = try select(sources)
        var resultsByRule = registeredRules.map { _ in [RuleAnalysisResult]() }
        for index in resultsByRule.indices {
            resultsByRule[index].reserveCapacity(selectedSources.count)
        }

        for selectedSource in selectedSources {
            let tree = Parser.parse(source: selectedSource.source.content)
            let converter = SourceLocationConverter(fileName: selectedSource.path.rawValue, tree: tree)
            let diagnostics = parseDiagnostics(
                tree: tree,
                converter: converter,
                sourcePath: selectedSource.path
            )

            if diagnostics.contains(where: { $0.severity == .error }) {
                for (index, registeredRule) in registeredRules.enumerated() {
                    resultsByRule[index].append(
                        RuleAnalysisResult(
                            descriptor: registeredRule.descriptor,
                            sourcePath: selectedSource.path,
                            outcome: .parseFailed(diagnostics: diagnostics)
                        )
                    )
                }
                continue
            }

            let context = AnalysisContext(sourceFile: tree, sourcePath: selectedSource.path)
            for (index, registeredRule) in registeredRules.enumerated() {
                resultsByRule[index].append(
                    execute(
                        registeredRule,
                        context: context,
                        tree: tree,
                        converter: converter
                    )
                )
            }
        }

        return AnalysisSnapshot(
            ruleDescriptors: registeredRules.map(\.descriptor),
            selectedSourcePaths: selectedSources.map(\.path),
            ruleResults: resultsByRule.flatMap { $0 }
        )
    }

    public func analyze<Rule: DebtRule>(
        _ source: SourceUnit,
        using rule: Rule
    ) throws -> RuleAnalysisResult {
        let snapshot = try analyze([source], using: rule)
        guard let result = snapshot.ruleResults.first else { throw RuleEngineError.noRulesSelected }
        return result
    }

    private func register(_ rules: [any DebtRule]) throws -> [RegisteredRule] {
        guard !rules.isEmpty else { throw RuleEngineError.noRulesSelected }
        var identities = Set<RuleIdentity>()
        return try rules.map { rule in
            let ruleType = type(of: rule)
            let descriptor = RuleDescriptor(
                identity: ruleType.identity,
                metadata: ruleType.metadata,
                contract: ruleType.contract
            )
            guard identities.insert(descriptor.identity).inserted else {
                throw RuleEngineError.duplicateRuleIdentity(descriptor.identity)
            }
            return RegisteredRule(rule: rule, descriptor: descriptor)
        }
    }

    private func select(_ sources: [SourceUnit]) throws -> [SelectedSource] {
        var sourcePaths = Set<SourcePath>()
        return try sources.map { source in
            let sourcePath = try SourcePath(source.path)
            guard sourcePaths.insert(sourcePath).inserted else {
                throw RuleEngineError.duplicateSourcePath(sourcePath)
            }
            return SelectedSource(source: source, path: sourcePath)
        }
    }

    private func parseDiagnostics(
        tree: SourceFileSyntax,
        converter: SourceLocationConverter,
        sourcePath: SourcePath
    ) -> [AnalysisDiagnostic] {
        ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
            let location = converter.location(for: diagnostic.position)
            return AnalysisDiagnostic(
                severity: diagnostic.diagMessage.severity == .error ? .error : .warning,
                message: diagnostic.message,
                location: SwiftDebtCore.SourceLocation(
                    file: sourcePath.rawValue,
                    line: location.line,
                    column: location.column
                )
            )
        }
    }

    private func execute(
        _ registeredRule: RegisteredRule,
        context: AnalysisContext,
        tree: SourceFileSyntax,
        converter: SourceLocationConverter
    ) -> RuleAnalysisResult {
        let descriptor = registeredRule.descriptor
        let sourcePath = context.sourcePath
        let buffer = EmissionBuffer { proposal in
            try validate(
                proposal,
                tree: tree,
                converter: converter,
                sourcePath: sourcePath,
                descriptor: descriptor
            )
        }
        let emitter = DetectionEmitter { node, continuitySubject, message in
            buffer.record(node: node, continuitySubject: continuitySubject, message: message)
        }

        do {
            try registeredRule.rule.detect(in: context, emit: emitter)
        } catch let unsupported as UnsupportedRuleAnalysis {
            if case .invalid(let reason) = buffer.takeAndClose() {
                return failed(descriptor, sourcePath, reason: "invalid emission: \(reason)")
            }
            guard Self.isValidMessage(unsupported.reason) else {
                return failed(descriptor, sourcePath, reason: "unsupported reason must be a nonempty single line")
            }
            return RuleAnalysisResult(
                descriptor: descriptor,
                sourcePath: sourcePath,
                outcome: .unsupported(reason: unsupported.reason)
            )
        } catch {
            if case .invalid(let reason) = buffer.takeAndClose() {
                return failed(descriptor, sourcePath, reason: "invalid emission: \(reason)")
            }
            return failed(descriptor, sourcePath, reason: "rule threw: \(String(describing: error))")
        }

        switch buffer.takeAndClose() {
        case .valid(let bufferedDetections):
            let detections = bufferedDetections.sorted { lhs, rhs in
                if lhs.location.line != rhs.location.line { return lhs.location.line < rhs.location.line }
                if lhs.location.column != rhs.location.column { return lhs.location.column < rhs.location.column }
                return lhs.message < rhs.message
            }
            return RuleAnalysisResult(
                descriptor: descriptor,
                sourcePath: sourcePath,
                outcome: .committed(detections)
            )
        case .invalid(let reason):
            return failed(descriptor, sourcePath, reason: "invalid emission: \(reason)")
        }
    }

    private func validate(
        _ proposal: EmissionProposal,
        tree: SourceFileSyntax,
        converter: SourceLocationConverter,
        sourcePath: SourcePath,
        descriptor: RuleDescriptor
    ) throws -> Detection {
        guard proposal.node.root.id == tree.id else { throw InvalidEmission.foreignNode }
        guard proposal.continuitySubject.root.id == tree.id else {
            throw InvalidEmission.foreignContinuitySubject
        }
        guard proposal.node.firstToken(viewMode: .sourceAccurate) != nil else {
            throw InvalidEmission.missingLocation
        }
        guard Self.isValidMessage(proposal.message) else { throw InvalidEmission.invalidMessage }
        let sourceLocation = converter.location(for: proposal.node.positionAfterSkippingLeadingTrivia)
        guard sourceLocation.line > 0, sourceLocation.column > 0 else {
            throw InvalidEmission.missingLocation
        }
        return Detection(
            ruleIdentity: descriptor.identity,
            semanticRevision: descriptor.semanticRevision,
            severity: descriptor.metadata.defaultSeverity,
            location: DetectionLocation(
                sourcePath: sourcePath,
                line: sourceLocation.line,
                column: sourceLocation.column
            ),
            message: proposal.message,
            structuralEvidence: try DetectionStructuralEvidenceFactory.make(
                subject: proposal.continuitySubject
            )
        )
    }

    private static func isValidMessage(_ message: String) -> Bool {
        guard !message.isEmpty, message.first?.isWhitespace == false, message.last?.isWhitespace == false else {
            return false
        }
        return !message.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }

    private func failed(
        _ descriptor: RuleDescriptor,
        _ sourcePath: SourcePath,
        reason: String
    ) -> RuleAnalysisResult {
        RuleAnalysisResult(descriptor: descriptor, sourcePath: sourcePath, outcome: .failed(reason: reason))
    }

}

private struct RegisteredRule {
    let rule: any DebtRule
    let descriptor: RuleDescriptor
}

private struct SelectedSource {
    let source: SourceUnit
    let path: SourcePath
}

private struct EmissionProposal {
    let node: Syntax
    let continuitySubject: Syntax
    let message: String
}

private final class EmissionBuffer {
    private let validate: (EmissionProposal) throws -> Detection
    private var isOpen = true
    private var detections: [Detection] = []
    private var invalidReason: String?

    init(validate: @escaping (EmissionProposal) throws -> Detection) {
        self.validate = validate
    }

    func record(node: Syntax, continuitySubject: Syntax, message: String) {
        guard isOpen, invalidReason == nil else { return }
        do {
            detections.append(
                try validate(
                    EmissionProposal(
                        node: node,
                        continuitySubject: continuitySubject,
                        message: message
                    )
                )
            )
        } catch {
            detections.removeAll(keepingCapacity: false)
            invalidReason = String(describing: error)
        }
    }

    func takeAndClose() -> BufferedEmissions {
        isOpen = false
        if let invalidReason { return .invalid(invalidReason) }
        return .valid(detections)
    }
}

private enum BufferedEmissions {
    case valid([Detection])
    case invalid(String)
}

private enum InvalidEmission: Error, CustomStringConvertible {
    case foreignNode
    case foreignContinuitySubject
    case invalidMessage
    case missingLocation

    var description: String {
        switch self {
        case .foreignNode:
            "node does not belong to the current source tree"
        case .foreignContinuitySubject:
            "continuity subject does not belong to the current source tree"
        case .invalidMessage:
            "message must be a nonempty single line without surrounding whitespace"
        case .missingLocation:
            "node does not identify a present source location"
        }
    }
}
