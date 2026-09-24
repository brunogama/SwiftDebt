import SwiftDebtCore
import SwiftSyntax

public struct ForceCastRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.code-smell"),
        id: RuleID(validated: "force-cast")
    )
    public static let metadata = RuleMetadata(
        name: "Force cast",
        defaultSeverity: .warning,
        remediation: "Use a checked cast or make the runtime type invariant explicit."
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports every syntactic as! occurrence in a successfully parsed source tree, including all #if branches.",
        rationale:
            "A forced cast traps when the runtime value has a different type. Syntax-only analysis does not evaluate conditional compilation or prove runtime types."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        ForceCastVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class ForceCastVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        report(node.questionOrExclamationMark)
        return .visitChildren
    }

    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        report(node.questionOrExclamationMark)
        return .visitChildren
    }

    private func report(_ marker: TokenSyntax?) {
        guard let marker, marker.tokenKind == .exclamationMark else { return }
        emit(
            at: marker,
            message:
                "This forced cast traps if the value has a different runtime type; use a checked cast or explicit invariant."
        )
    }
}
