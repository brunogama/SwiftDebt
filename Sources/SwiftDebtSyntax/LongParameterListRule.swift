import SwiftDebtCore
import SwiftSyntax

/// Reports function and initializer declarations with at least six parameters.
public struct LongParameterListRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.refactoring"),
        id: RuleID(validated: "long-parameter-list")
    )
    public static let metadata = RuleMetadata(
        name: "Long Parameter List",
        defaultSeverity: .warning,
        remediation: "Group related parameters in a meaningful value type or derive values from an existing object.",
        documentationURL: "https://brunogama.github.io/SwiftDebt/documentation/swiftdebtkit/longparameterlist"
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Reports function and initializer declarations with six or more declared parameters.",
        rationale:
            "Many independent arguments make calls harder to read and easier to misconfigure. Some APIs legitimately need them, so review the relationship among the values."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        LongParameterListVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class LongParameterListVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let count = node.signature.parameterClause.parameters.count
        if count >= 6 {
            emit(at: node.name, message: "Function '\(node.name.text)' declares \(count) parameters (threshold: 6).")
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let count = node.signature.parameterClause.parameters.count
        if count >= 6 {
            emit(at: node.initKeyword, message: "Initializer declares \(count) parameters (threshold: 6).")
        }
        return .visitChildren
    }
}
