extension RefactoringCodeSmellCatalog {
    static let researchBehaviorSmells: [RefactoringCodeSmell] = [
        RefactoringCodeSmell(
            name: "Speculative Generality", supportState: .research,
            minimumPredicate: "Extension points lack observed use and a justified variation contract.",
            requiredEvidence: ["repository usage", "variation intent"],
            scope: "abstraction and its clients",
            falsePositiveRisk: "A public API may serve clients outside the repository.",
            falseNegativeRisk: "Current uses can mask unnecessary flexibility.",
            explanationContract: "Show extension points, observed uses, and a simplification option."
        ),
        RefactoringCodeSmell(
            name: "Temporary Field", supportState: .research,
            minimumPredicate: "A field is meaningful only during one object-lifetime phase.",
            requiredEvidence: ["field reads and writes", "lifetime phase"],
            scope: "type state transitions",
            falsePositiveRisk: "A sparse field may be valid optional state.",
            falseNegativeRisk: "External mutation can hide the temporary phase.",
            explanationContract: "Show phase-limited uses and an extract-state option."
        ),
        RefactoringCodeSmell(
            name: "Message Chains", supportState: .research,
            minimumPredicate: "A resolved access chain exposes navigation through owners.",
            requiredEvidence: ["resolved access graph", "delegation boundary"],
            scope: "expression and accessed owners",
            falsePositiveRisk: "A fluent API may deliberately return its own receiver.",
            falseNegativeRisk: "Computed helpers can hide navigation.",
            explanationContract: "Show resolved chain owners and a hide-delegate option."
        ),
        RefactoringCodeSmell(
            name: "Middle Man", supportState: .research,
            minimumPredicate: "Resolved forwarding behavior dominates a type's useful behavior.",
            requiredEvidence: ["compiler-backed ownership", "resolved forwarding calls"],
            scope: "type and delegated methods",
            falsePositiveRisk: "A facade may intentionally stabilize an external API.",
            falseNegativeRisk: "Forwarding through protocols can evade syntax matching.",
            explanationContract: "Show delegate targets and a direct-call option."
        ),
        RefactoringCodeSmell(
            name: "Insider Trading", supportState: .research,
            minimumPredicate: "Types exchange internal state beyond their intended collaboration.",
            requiredEvidence: ["resolved cross-type access", "visibility", "ownership"],
            scope: "collaborating types",
            falsePositiveRisk: "Close collaborators may intentionally share private details.",
            falseNegativeRisk: "Dynamic access can hide coupling.",
            explanationContract: "Show cross-type accesses and an ownership change."
        ),
        RefactoringCodeSmell(
            name: "Alternative Classes with Different Interfaces", supportState: .research,
            minimumPredicate: "Two role-equivalent types expose needlessly different APIs.",
            requiredEvidence: ["role equivalence", "API structure", "behavior validation"],
            optionalEvidence: ["semantic similarity candidates"],
            scope: "pair of repository types",
            falsePositiveRisk: "Similar names can mask different contracts.",
            falseNegativeRisk: "Different vocabulary can hide equivalent roles.",
            explanationContract: "Show matched roles, API differences, and a unification option."
        ),
        RefactoringCodeSmell(
            name: "Data Class", supportState: .research,
            minimumPredicate: "A type owns data while relevant behavior lives elsewhere.",
            requiredEvidence: ["data ownership", "behavior placement", "external uses"],
            scope: "type and repository clients",
            falsePositiveRisk: "A data transfer object can be intentionally behavior-free.",
            falseNegativeRisk: "Behavior may live in unavailable external modules.",
            explanationContract: "Show external behavior and a move-method option."
        ),
        RefactoringCodeSmell(
            name: "Refused Bequest", supportState: .research,
            minimumPredicate: "A subtype cannot use or uphold inherited behavior.",
            requiredEvidence: ["inheritance contract", "use and override behavior"],
            scope: "subtype and inherited API",
            falsePositiveRisk: "A subtype can validly narrow use without violating its contract.",
            falseNegativeRisk: "External consumers can reveal a contract problem.",
            explanationContract: "Show inherited behavior and a composition option."
        ),
    ]
}
