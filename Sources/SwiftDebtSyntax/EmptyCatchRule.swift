import SwiftDebtCore
import SwiftSyntax

public struct EmptyCatchRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.code-smell"),
        id: RuleID(validated: "empty-catch")
    )
    public static let metadata = RuleMetadata(
        name: "Empty catch",
        defaultSeverity: .warning,
        remediation: "Handle or propagate the error; an intentionally ignored error remains observable."
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports catch clauses with no code block items; comments and trivia do not count. Every #if branch in a successfully parsed source tree is inspected.",
        rationale:
            "An empty catch body discards an error without executable handling. Syntax-only analysis does not evaluate conditional compilation or infer intent."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        EmptyCatchVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class EmptyCatchVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        guard node.body.statements.isEmpty else { return .visitChildren }
        emit(
            at: node.catchKeyword,
            message: "This catch clause has an empty body and discards the error; handle or propagate it."
        )
        return .visitChildren
    }
}
