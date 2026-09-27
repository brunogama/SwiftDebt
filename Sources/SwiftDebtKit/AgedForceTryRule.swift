import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax
import SwiftSyntax

struct AgedForceTryRule: DebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt"),
        id: RuleID(validated: "aged-force-try")
    )
    static let metadata = RuleMetadata(
        name: "Aged force try",
        defaultSeverity: .warning,
        remediation:
            "Handle or propagate the error, prioritizing force tries retained beyond the commit that introduced them."
    )
    static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports a syntactic try! when source-validated git-blame-v1 evidence says its line was last changed "
            + "before the clean captured HEAD. Provider loss or incomplete line evidence is unsupported, not absence.",
        rationale:
            "A force try can terminate the process, and surviving a later commit is explicit evidence of retained debt."
    )

    let availability: GitBlameEvidenceAvailability

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        guard case .available(let evidence) = availability else {
            let reason = availability.unavailableReason
            throw UnsupportedRuleAnalysis(
                reason: "git-blame-v1 unavailable (\(reason?.code ?? "unknown")): "
                    + (reason?.message ?? "No canonical Git blame evidence was produced.")
            )
        }
        guard let facts = evidence.facts(for: context.sourcePath),
            facts.headRevision == evidence.headRevision
        else {
            throw UnsupportedRuleAnalysis(
                reason: "git-blame-v1 has no source-validated facts for \(context.sourcePath.rawValue)."
            )
        }

        let visitor = AgedForceTryVisitor(
            facts: facts,
            headRevision: evidence.headRevision,
            converter: SourceLocationConverter(fileName: context.sourcePath.rawValue, tree: context.sourceFile),
            emit: emit
        )
        visitor.walk(context.sourceFile)
        if visitor.missingLineEvidence {
            throw UnsupportedRuleAnalysis(
                reason: "git-blame-v1 line evidence does not cover every observed try! syntax subject."
            )
        }
    }
}

private final class AgedForceTryVisitor: SyntaxVisitor {
    private let facts: GitBlameSourceFacts
    private let headRevision: GitRevisionID
    private let converter: SourceLocationConverter
    private let emit: DetectionEmitter
    var missingLineEvidence = false

    init(
        facts: GitBlameSourceFacts,
        headRevision: GitRevisionID,
        converter: SourceLocationConverter,
        emit: DetectionEmitter
    ) {
        self.facts = facts
        self.headRevision = headRevision
        self.converter = converter
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        guard let marker = node.questionOrExclamationMark,
            marker.tokenKind == .exclamationMark
        else {
            return .visitChildren
        }
        let line = converter.location(for: marker.positionAfterSkippingLeadingTrivia).line
        guard let revision = facts.revision(forLine: line) else {
            missingLineEvidence = true
            return .visitChildren
        }
        guard revision != headRevision else { return .visitChildren }
        emit(
            at: marker,
            continuitySubject: node,
            message:
                "This try! last changed in Git revision \(revision.rawValue), which predates the captured Git HEAD; "
                + "handle or propagate the error."
        )
        return .visitChildren
    }
}
