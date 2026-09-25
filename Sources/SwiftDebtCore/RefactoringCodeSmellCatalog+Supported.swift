extension RefactoringCodeSmellCatalog {
    static let supportedSyntaxSmells: [RefactoringCodeSmell] = [
        RefactoringCodeSmell(
            name: "Long Function", supportState: .supported,
            ruleIdentity: "swiftdebt.refactoring.long-function", semanticRevision: 1,
            minimumPredicate: "Function body exceeds the documented line threshold.",
            requiredEvidence: ["syntax", "body line count"], scope: "one parsed function",
            falsePositiveRisk: "Generated or deliberately linear code can be long but clear.",
            falseNegativeRisk: "Short functions can still have too many responsibilities.",
            explanationContract: "Show the measured line count, threshold, and an extraction direction.",
            fixtureReferences: ["Tests/SwiftDebtSyntaxTests/RefactoringSmellRuleTests.swift"]
        ),
        RefactoringCodeSmell(
            name: "Long Parameter List", supportState: .supported,
            ruleIdentity: "swiftdebt.refactoring.long-parameter-list", semanticRevision: 1,
            minimumPredicate: "Declared parameter count exceeds the documented threshold.",
            requiredEvidence: ["syntax", "parameter count"], scope: "one parsed callable",
            falsePositiveRisk: "A stable data transfer boundary may need many independent values.",
            falseNegativeRisk: "A short list may still group unrelated concepts.",
            explanationContract: "Show the parameter count, threshold, and a parameter-object direction.",
            fixtureReferences: ["Tests/SwiftDebtSyntaxTests/RefactoringSmellRuleTests.swift"]
        ),
        RefactoringCodeSmell(
            name: "Global Data", supportState: .supported,
            ruleIdentity: "swiftdebt.refactoring.global-data", semanticRevision: 1,
            minimumPredicate: "A mutable declaration occurs at file scope.",
            requiredEvidence: ["syntax", "declaration scope"], scope: "one parsed source file",
            falsePositiveRisk: "A guarded global may have controlled access outside syntax evidence.",
            falseNegativeRisk: "Mutable shared state can hide behind a static property.",
            explanationContract: "Show the mutable declaration and an ownership direction.",
            fixtureReferences: ["Tests/SwiftDebtSyntaxTests/RefactoringSmellRuleTests.swift"]
        ),
        RefactoringCodeSmell(
            name: "Large Class", supportState: .supported,
            ruleIdentity: "swiftdebt.refactoring.large-class", semanticRevision: 1,
            minimumPredicate: "A nominal type body exceeds the documented line threshold.",
            requiredEvidence: ["syntax", "type body line count"], scope: "one parsed nominal type",
            falsePositiveRisk: "A large cohesive declaration can be appropriate.",
            falseNegativeRisk: "Responsibilities can be scattered across small extensions.",
            explanationContract: "Show the measured type size, threshold, and a responsibility split.",
            fixtureReferences: ["Tests/SwiftDebtSyntaxTests/RefactoringSmellRuleTests.swift"]
        ),
    ]
}
