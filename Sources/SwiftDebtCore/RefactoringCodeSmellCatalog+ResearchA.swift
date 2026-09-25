extension RefactoringCodeSmellCatalog {
    static let researchSmells: [RefactoringCodeSmell] = researchStructureSmells + researchBehaviorSmells

    static let researchStructureSmells: [RefactoringCodeSmell] = [
        RefactoringCodeSmell(
            name: "Duplicated Code", supportState: .research,
            minimumPredicate: "Two concrete bodies have meaningful normalized equivalence.",
            requiredEvidence: ["structural normalization", "matching source spans"],
            scope: "repository declarations",
            falsePositiveRisk: "Similar syntax may encode different domain behavior.",
            falseNegativeRisk: "Equivalent behavior can use different syntax.",
            explanationContract: "Show both spans, their normalized match, and an extraction option."
        ),
        RefactoringCodeSmell(
            name: "Mutable Data", supportState: .research,
            minimumPredicate: "Mutation and aliasing expose state outside a clear owner.",
            requiredEvidence: ["mutation", "aliasing", "ownership"],
            scope: "repository state flow",
            falsePositiveRisk: "Local controlled mutation can be harmless.",
            falseNegativeRisk: "Indirect writes can escape a syntax-only analysis.",
            explanationContract: "Show writes, aliases, owner, and an encapsulation option."
        ),
        RefactoringCodeSmell(
            name: "Divergent Change", supportState: .research,
            minimumPredicate: "One unit changes repeatedly for distinct reasons.",
            requiredEvidence: ["Git history", "change-purpose evidence"],
            scope: "history of a repository unit",
            falsePositiveRisk: "A broad commit can look like multiple responsibilities.",
            falseNegativeRisk: "Sparse history can hide separate change reasons.",
            explanationContract: "Show distinct change groups and a responsibility split."
        ),
        RefactoringCodeSmell(
            name: "Shotgun Surgery", supportState: .research,
            minimumPredicate: "One kind of change repeatedly requires coordinated edits across units.",
            requiredEvidence: ["Git history", "co-change relationships"],
            scope: "repository history",
            falsePositiveRisk: "Mechanical updates can create unrelated co-change.",
            falseNegativeRisk: "Few observed changes can conceal coordination cost.",
            explanationContract: "Show repeated edit sets and a consolidation direction."
        ),
        RefactoringCodeSmell(
            name: "Feature Envy", supportState: .research,
            minimumPredicate: "A method accesses resolved foreign members more than its owner's members.",
            requiredEvidence: ["compiler-backed name binding", "member ownership"],
            scope: "method and accessed types",
            falsePositiveRisk: "Foreign access can be a deliberate orchestration role.",
            falseNegativeRisk: "Dispatch and generated access can hide ownership.",
            explanationContract: "Show resolved owners, access counts, and a move-method option."
        ),
        RefactoringCodeSmell(
            name: "Data Clumps", supportState: .research,
            minimumPredicate: "A type-compatible parameter or property group repeats across declarations.",
            requiredEvidence: ["repository structural groups", "type compatibility"],
            scope: "repository declarations",
            falsePositiveRisk: "A repeated group may represent unrelated roles.",
            falseNegativeRisk: "Renamed or wrapped values can hide the same concept.",
            explanationContract: "Show group members, compared declarations, and an extract-type option."
        ),
        RefactoringCodeSmell(
            name: "Repeated Switches", supportState: .research,
            minimumPredicate: "Normalized dispatch over one discriminator repeats across units.",
            requiredEvidence: ["repository switch structure", "discriminator identity"],
            scope: "repository switch statements",
            falsePositiveRisk: "Repeated exhaustive handling can be intentional at boundaries.",
            falseNegativeRisk: "Equivalent dispatch can use if chains or different spelling.",
            explanationContract: "Show switches, discriminator, cases, and a polymorphism option."
        ),
        RefactoringCodeSmell(
            name: "Lazy Element", supportState: .research,
            minimumPredicate: "An abstraction adds little behavior or role under observed uses.",
            requiredEvidence: ["repository usage", "abstraction role"],
            scope: "type or method and its callers",
            falsePositiveRisk: "An intentional extension boundary can appear unused today.",
            falseNegativeRisk: "External clients may use an apparently small API.",
            explanationContract: "Show the abstraction's uses and a safe inline option."
        ),
    ]
}
