import SwiftDebtCore
import SwiftSyntax

/// Reports mutable variables declared directly at file scope.
public struct GlobalDataRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.refactoring"),
        id: RuleID(validated: "global-data")
    )
    public static let metadata = RuleMetadata(
        name: "Global Data",
        defaultSeverity: .warning,
        remediation:
            "Move mutable state behind an owner with explicit access and synchronization, or pass a value to its users.",
        documentationURL: "https://brunogama.github.io/SwiftDebt/documentation/swiftdebtkit/globaldata"
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports mutable var declarations directly in the source file's top-level statement list. Declarations inside #if clauses are outside this rule.",
        rationale:
            "File-scope mutable state can be changed by distant code, obscuring ownership and increasing concurrency risk. This syntax check cannot prove reachability or unsafe access."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        for statement in context.sourceFile.statements {
            guard let declaration = statement.item.as(VariableDeclSyntax.self),
                declaration.bindingSpecifier.tokenKind == .keyword(.var)
            else { continue }
            emit(at: declaration.bindingSpecifier, message: "A mutable variable is declared at file scope.")
        }
    }
}
