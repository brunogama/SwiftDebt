import SwiftDebtCore
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

public struct RuleEngine {
    public init() {}

    public func analyze<Rule: DebtRule>(
        _ sources: [SourceUnit],
        using rule: Rule
    ) throws -> AnalysisSnapshot {
        let results = try sources.map { try analyze($0, using: rule) }
        return AnalysisSnapshot(
            ruleDescriptor: descriptor(for: Rule.self),
            selectedSourcePaths: results.map(\.sourcePath),
            ruleResults: results
        )
    }

    public func analyze<Rule: DebtRule>(
        _ source: SourceUnit,
        using rule: Rule
    ) throws -> RuleAnalysisResult {
        let sourcePath = try SourcePath(source.path)
        let descriptor = descriptor(for: Rule.self)
        let tree = Parser.parse(source: source.content)
        let converter = SourceLocationConverter(fileName: sourcePath.rawValue, tree: tree)
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
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
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            return RuleAnalysisResult(
                descriptor: descriptor,
                sourcePath: sourcePath,
                outcome: .parseFailed(diagnostics: diagnostics)
            )
        }

        let buffer = EmissionBuffer { proposal in
            try validate(
                proposal,
                tree: tree,
                converter: converter,
                sourcePath: sourcePath,
                descriptor: descriptor
            )
        }
        let emitter = DetectionEmitter { node, message in
            buffer.record(node: node, message: message)
        }
        let context = AnalysisContext(sourceFile: tree, sourcePath: sourcePath)

        do {
            try rule.detect(in: context, emit: emitter)
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
            message: proposal.message
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

    private func descriptor<Rule: DebtRule>(for ruleType: Rule.Type) -> RuleDescriptor {
        RuleDescriptor(
            identity: ruleType.identity,
            metadata: ruleType.metadata,
            contract: ruleType.contract
        )
    }
}

private struct EmissionProposal {
    let node: Syntax
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

    func record(node: Syntax, message: String) {
        guard isOpen, invalidReason == nil else { return }
        do {
            detections.append(try validate(EmissionProposal(node: node, message: message)))
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
    case invalidMessage
    case missingLocation

    var description: String {
        switch self {
        case .foreignNode:
            "node does not belong to the current source tree"
        case .invalidMessage:
            "message must be a nonempty single line without surrounding whitespace"
        case .missingLocation:
            "node does not identify a present source location"
        }
    }
}
