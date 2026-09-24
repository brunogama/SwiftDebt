import SwiftDebtCore
import SwiftSyntax

/// Reports class declarations with at least 20 direct members.
public struct LargeClassRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.refactoring"),
        id: RuleID(validated: "large-class")
    )
    public static let metadata = RuleMetadata(
        name: "Large Class",
        defaultSeverity: .warning,
        remediation:
            "Identify groups of related state and behavior, then extract a type with one clear responsibility.",
        documentationURL: "https://brunogama.github.io/SwiftDebt/documentation/swiftdebtkit/largeclass"
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Reports class declarations containing 20 or more direct member declarations.",
        rationale:
            "Many members may indicate that a class owns several responsibilities. Extensions and generated members are outside this syntax count, and size alone does not prove a design problem."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        LargeClassVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class LargeClassVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let count = node.memberBlock.members.count
        if count >= 20 {
            emit(at: node.name, message: "Class '\(node.name.text)' declares \(count) direct members (threshold: 20).")
        }
        return .visitChildren
    }
}
