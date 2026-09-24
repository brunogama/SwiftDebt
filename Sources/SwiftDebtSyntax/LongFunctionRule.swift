import SwiftDebtCore
import SwiftSyntax

/// Reports functions with at least 20 top-level body statements.
public struct LongFunctionRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.refactoring"),
        id: RuleID(validated: "long-function")
    )
    public static let metadata = RuleMetadata(
        name: "Long Function",
        defaultSeverity: .warning,
        remediation: "Extract a coherent group of statements into a named function, then check its inputs and outputs.",
        documentationURL: "https://brunogama.github.io/SwiftDebt/documentation/swiftdebtkit/longfunction"
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Reports function declarations with 20 or more top-level statements in the body.",
        rationale:
            "A large sequence of steps makes one function harder to scan and gives changes more reasons to touch it. The threshold is a review signal, not proof that extraction improves the design."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        LongFunctionVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class LongFunctionVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body, body.statements.count >= 20 {
            emit(
                at: node.name,
                message:
                    "Function '\(node.name.text)' has \(body.statements.count) top-level statements (threshold: 20).")
        }
        return .visitChildren
    }
}
