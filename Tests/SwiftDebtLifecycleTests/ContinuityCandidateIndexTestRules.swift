import SwiftDebtCore
import SwiftDebtSyntax
import SwiftSyntax

struct NamedFunctionRule: DebtRule {
    static let identity = LifecycleRuleV1.identity
    static let metadata = LifecycleRuleV1.metadata
    static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Observes one named function per SourceUnit.",
        rationale: "Provides distinct structural anchors for reconciliation tests."
    )

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        if let name = Array(context.sourceFile.tokens(viewMode: .sourceAccurate)).dropFirst().first {
            emit(at: name, message: "Named function detected.")
        }
    }
}

struct IncompatibleNamedFunctionRule: DebtRule {
    static let identity = NamedFunctionRule.identity
    static let metadata = NamedFunctionRule.metadata
    static let contract: RuleContract = {
        guard let revision = SemanticRevision(2) else {
            preconditionFailure("Two is a valid Semantic Revision.")
        }
        return RuleContract(
            semanticRevision: revision,
            semantics: "Changes the named function debt definition.",
            rationale: "Exercises blocked semantic comparisons."
        )
    }()

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        try NamedFunctionRule().detect(in: context, emit: emit)
    }
}
