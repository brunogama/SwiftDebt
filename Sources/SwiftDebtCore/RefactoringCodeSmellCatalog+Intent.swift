extension RefactoringCodeSmellCatalog {
    static let intentDependentSmells: [RefactoringCodeSmell] = [
        RefactoringCodeSmell(
            name: "Mysterious Name", supportState: .notReliablyObservable,
            minimumPredicate: "The name obscures the intended domain meaning.",
            requiredEvidence: ["domain naming intent"], scope: "identifier and its use context",
            falsePositiveRisk: "Short conventional names can be clear in context.",
            falseNegativeRisk: "A plausible name can still misrepresent intent.",
            explanationContract: "Show the identifier, its use context, and a concrete rename."
        ),
        RefactoringCodeSmell(
            name: "Primitive Obsession", supportState: .notReliablyObservable,
            minimumPredicate: "Several primitives encode a domain concept needing its own type.",
            requiredEvidence: ["domain meaning", "value invariants"],
            scope: "repository data model",
            falsePositiveRisk: "A primitive can be the simplest correct representation.",
            falseNegativeRisk: "Aliases can hide an unmodeled domain concept.",
            explanationContract: "Show the concept, repeated invariants, and a value-type option."
        ),
        RefactoringCodeSmell(
            name: "Loops", supportState: .notReliablyObservable,
            minimumPredicate: "Replacing a specific loop improves clarity for its intent.",
            requiredEvidence: ["behavioral intent", "transformation quality"],
            scope: "loop and its surrounding operation",
            falsePositiveRisk: "A loop can be clearer than a chained transform.",
            falseNegativeRisk: "Complex control flow can obscure a useful replacement.",
            explanationContract: "Show the loop's purpose and a behavior-preserving replacement."
        ),
        RefactoringCodeSmell(
            name: "Comments", supportState: .notReliablyObservable,
            minimumPredicate: "A comment compensates for code that fails to express its behavior.",
            requiredEvidence: ["comment intent", "code behavior"],
            scope: "comment and adjacent code",
            falsePositiveRisk: "Documentation and rationale comments are often useful.",
            falseNegativeRisk: "Unclear behavior may have no comment at all.",
            explanationContract: "Show why the comment is compensatory and how code can express it."
        ),
    ]
}
