import SwiftDebtCore

struct DataClumpsRepositoryRule {
    static let identity = "swiftdebt.refactoring.data-clumps"
    static let semanticRevision: UInt = 1
    static let name = "Data Clumps"
    static let predicate =
        "A closed group of at least the configured number of identical local-name and normalized-type elements occurs in at least the configured number of parameter or property units."
    static let documentationURL =
        "https://brunogama.github.io/SwiftDebt/documentation/swiftdebtkit/dataclumps"

    func analyze(
        units: [DataClumpUnit],
        snapshotDigest: RepositoryDigest,
        configuration: RepositoryAnalysisConfiguration,
        inheritedIssues: [RepositoryEvidenceIssue]
    ) throws -> RepositoryRuleEvidence {
        var issues = inheritedIssues
        guard units.count <= configuration.maximumAnalysisUnitsPerRule else {
            issues.append(
                try RepositoryEvidenceIssue(
                    code: "analysis-unit-budget-exceeded",
                    message:
                        "Data Clumps selected \(units.count) units, exceeding the configured limit of \(configuration.maximumAnalysisUnitsPerRule)."
                )
            )
            return try result(detections: [], issues: issues)
        }
        let groups: [DataClumpGroup]
        do {
            groups = try closedGroups(
                units: units,
                minimumElements: configuration.minimumDataClumpElements,
                minimumOccurrences: configuration.minimumDataClumpOccurrences,
                maximumComparisons: configuration.maximumDataClumpComparisons
            )
        } catch DataClumpEnumerationError.comparisonBudgetExceeded {
            issues.append(
                try RepositoryEvidenceIssue(
                    code: "comparison-budget-exceeded",
                    message:
                        "Data Clumps exhausted its configured limit of \(configuration.maximumDataClumpComparisons) set comparisons before exact candidate enumeration completed."
                )
            )
            return try result(detections: [], issues: issues)
        }
        if groups.count > configuration.maximumDetectionsPerRule {
            issues.append(
                try RepositoryEvidenceIssue(
                    code: "detection-budget-exceeded",
                    message:
                        "Data Clumps produced \(groups.count) groups, exceeding the configured limit of \(configuration.maximumDetectionsPerRule)."
                )
            )
        }
        let selectedGroups = groups.prefix(configuration.maximumDetectionsPerRule)
        let detections = try selectedGroups.map { group in
            try detection(group, snapshotDigest: snapshotDigest, units: units, configuration: configuration)
        }
        return try result(detections: detections, issues: issues)
    }

    private func result(
        detections: [RepositoryDetection],
        issues: [RepositoryEvidenceIssue]
    ) throws -> RepositoryRuleEvidence {
        RepositoryRuleEvidence(
            ruleIdentity: Self.identity,
            semanticRevision: Self.semanticRevision,
            name: Self.name,
            completionState: issues.isEmpty ? .complete : .incomplete,
            predicate: Self.predicate,
            capabilities: [try repositoryCapability("exact-data-clump-enumeration", issues: issues)],
            detections: detections,
            issues: issues
        )
    }

    private func closedGroups(
        units: [DataClumpUnit],
        minimumElements: Int,
        minimumOccurrences: Int,
        maximumComparisons: Int
    ) throws -> [DataClumpGroup] {
        var budget = DataClumpComparisonBudget(limit: maximumComparisons)
        var candidates = Set<[DataClumpElement]>()
        guard units.count >= minimumOccurrences else { return [] }
        for firstIndex in 0..<units.count {
            for secondIndex in (firstIndex + 1)..<units.count {
                try budget.consume()
                let overlap = units[firstIndex].elements.intersection(units[secondIndex].elements).sorted()
                if overlap.count >= minimumElements {
                    candidates.insert(overlap)
                }
            }
        }

        var closed: [[DataClumpElement]: [Int]] = [:]
        for candidate in candidates.sorted(by: elementListOrder) {
            let candidateSet = Set(candidate)
            var support: [Int] = []
            for index in units.indices {
                try budget.consume()
                if units[index].elements.isSuperset(of: candidateSet) {
                    support.append(index)
                }
            }
            guard support.count >= minimumOccurrences, let first = support.first else { continue }
            var closure = units[first].elements
            for index in support.dropFirst() {
                try budget.consume()
                closure.formIntersection(units[index].elements)
            }
            if closure.count >= minimumElements {
                // A closure contains its candidate, so both have the same supporting units.
                closed[closure.sorted()] = support
            }
        }

        return closed.map { elements, support in
            DataClumpGroup(elements: elements, unitIndices: support)
        }.sorted(by: groupOrder)
    }

    private func detection(
        _ group: DataClumpGroup,
        snapshotDigest: RepositoryDigest,
        units: [DataClumpUnit],
        configuration: RepositoryAnalysisConfiguration
    ) throws -> RepositoryDetection {
        let compared = group.unitIndices.map { units[$0].comparedUnit }.sorted(by: comparedUnitOrder)
        let primary = compared[0].location
        let values = group.elements.map(\.displayValue)
        let fingerprint = try detectionFingerprint(
            ruleIdentity: Self.identity,
            values: values,
            units: compared
        )
        let refactoring =
            compared.contains { $0.kind != .nominalProperties }
            ? "Introduce a parameter object or value type that owns this repeated group."
            : "Extract the repeated properties into a focused value type and compose it from each owner."
        let facts = [
            RepositoryObservedFact(
                kind: "shared-elements",
                value: values.joined(separator: ", "),
                evidenceClass: .structural,
                locations: compared.map(\.location)
            ),
            RepositoryObservedFact(
                kind: "occurrence-count",
                value: String(compared.count),
                evidenceClass: .metric,
                locations: compared.map(\.location)
            ),
        ]
        return RepositoryDetection(
            selector: RepositoryDetectionSelector(
                ruleIdentity: Self.identity,
                semanticRevision: Self.semanticRevision,
                snapshotDigest: snapshotDigest,
                location: primary,
                evidenceFingerprint: fingerprint
            ),
            title: Self.name,
            primaryLocation: primary,
            summary:
                "\(group.elements.count) compatible elements recur across \(compared.count) declaration units.",
            explanation: RepositoryDetectionExplanation(
                predicate:
                    "Observed \(group.elements.count) shared elements in \(compared.count) units; required at least \(configuration.minimumDataClumpElements) elements in \(configuration.minimumDataClumpOccurrences) units.",
                decisiveFacts: facts,
                comparedUnits: compared,
                evidenceClasses: [.syntax, .metric, .structural],
                limitations: [
                    "Type compatibility is exact normalized syntax, not compiler-resolved type identity.",
                    "Equal names and type spellings can represent unrelated concepts in different binding contexts.",
                ],
                refactoringDirection: refactoring,
                documentationURL: Self.documentationURL
            )
        )
    }

    private func groupOrder(_ lhs: DataClumpGroup, _ rhs: DataClumpGroup) -> Bool {
        let left = lhs.elements.map(\.displayValue).joined(separator: "|")
        let right = rhs.elements.map(\.displayValue).joined(separator: "|")
        if left != right { return left < right }
        return lhs.unitIndices.lexicographicallyPrecedes(rhs.unitIndices)
    }

    private func elementListOrder(_ lhs: [DataClumpElement], _ rhs: [DataClumpElement]) -> Bool {
        lhs.lexicographicallyPrecedes(rhs)
    }
}
