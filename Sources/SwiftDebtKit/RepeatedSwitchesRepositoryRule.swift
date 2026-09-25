import SwiftDebtCore

struct RepeatedSwitchesRepositoryRule {
    static let identity = "swiftdebt.refactoring.repeated-switches"
    static let semanticRevision: UInt = 1
    static let name = "Repeated Switches"
    static let predicate =
        "At least the configured number of switches in one textual module/type scope have the same simple discriminator and ordered normalized case-label shape."
    static let documentationURL =
        "https://brunogama.github.io/SwiftDebt/documentation/swiftdebtkit/repeatedswitches"

    func analyze(
        units: [RepeatedSwitchUnit],
        conditionalSwitchLocations: [SourceLocation],
        snapshotDigest: RepositoryDigest,
        configuration: RepositoryAnalysisConfiguration,
        inheritedIssues: [RepositoryEvidenceIssue]
    ) throws -> RepositoryRuleEvidence {
        var issues = inheritedIssues
        if !conditionalSwitchLocations.isEmpty {
            issues.append(
                try RepositoryEvidenceIssue(
                    code: "conditional-switch-cases-unavailable",
                    message:
                        "Repeated Switches could not select active branches for \(conditionalSwitchLocations.count) switch statements containing conditional-compilation case elements."
                )
            )
        }
        guard units.count <= configuration.maximumAnalysisUnitsPerRule else {
            issues.append(
                try RepositoryEvidenceIssue(
                    code: "analysis-unit-budget-exceeded",
                    message:
                        "Repeated Switches selected \(units.count) units, exceeding the configured limit of \(configuration.maximumAnalysisUnitsPerRule)."
                )
            )
            return try result(detections: [], issues: issues)
        }

        let grouped = Dictionary(grouping: units) {
            RepeatedSwitchKey(scope: $0.scope, discriminator: $0.discriminator, caseShape: $0.caseShape)
        }
        let groups = grouped.compactMap { key, occurrences -> RepeatedSwitchGroup? in
            guard occurrences.count >= configuration.minimumRepeatedSwitchOccurrences else { return nil }
            return RepeatedSwitchGroup(
                key: key,
                occurrences: occurrences.sorted(by: repeatedSwitchUnitOrder)
            )
        }.sorted(by: groupOrder)
        if groups.count > configuration.maximumDetectionsPerRule {
            issues.append(
                try RepositoryEvidenceIssue(
                    code: "detection-budget-exceeded",
                    message:
                        "Repeated Switches produced \(groups.count) groups, exceeding the configured limit of \(configuration.maximumDetectionsPerRule)."
                )
            )
        }
        let detections = try groups.prefix(configuration.maximumDetectionsPerRule).map { group in
            try detection(
                group.key,
                occurrences: group.occurrences,
                snapshotDigest: snapshotDigest,
                configuration: configuration
            )
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
            capabilities: [try repositoryCapability("exact-repeated-switch-enumeration", issues: issues)],
            detections: detections,
            issues: issues
        )
    }

    private func detection(
        _ key: RepeatedSwitchKey,
        occurrences: [RepeatedSwitchUnit],
        snapshotDigest: RepositoryDigest,
        configuration: RepositoryAnalysisConfiguration
    ) throws -> RepositoryDetection {
        let compared = occurrences.map(\.comparedUnit).sorted(by: comparedUnitOrder)
        let primary = compared[0].location
        let values = [key.scope, key.discriminator] + key.caseShape
        let fingerprint = try detectionFingerprint(
            ruleIdentity: Self.identity,
            values: values,
            units: compared
        )
        let facts = [
            RepositoryObservedFact(
                kind: "textual-scope",
                value: key.scope,
                evidenceClass: .syntax,
                locations: compared.map(\.location)
            ),
            RepositoryObservedFact(
                kind: "discriminator",
                value: key.discriminator,
                evidenceClass: .structural,
                locations: compared.map(\.location)
            ),
            RepositoryObservedFact(
                kind: "ordered-case-shape",
                value: key.caseShape.joined(separator: " | "),
                evidenceClass: .structural,
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
                "The same \(key.caseShape.count)-branch switch shape recurs \(compared.count) times for \(key.discriminator).",
            explanation: RepositoryDetectionExplanation(
                predicate:
                    "Observed \(compared.count) switches with the same simple discriminator and ordered case labels; required at least \(configuration.minimumRepeatedSwitchOccurrences).",
                decisiveFacts: facts,
                comparedUnits: compared,
                evidenceClasses: [.syntax, .structural],
                limitations: [
                    "Discriminator identity is exact syntax within a textual module/type scope, not compiler name binding.",
                    "Case bodies do not participate in the dispatch-shape key.",
                ],
                refactoringDirection:
                    "Centralize the dispatch or replace the repeated type/code distinction with polymorphic behavior.",
                documentationURL: Self.documentationURL
            )
        )
    }

    private func groupOrder(_ lhs: RepeatedSwitchGroup, _ rhs: RepeatedSwitchGroup) -> Bool {
        let left = lhs.occurrences[0].location
        let right = rhs.occurrences[0].location
        if sourceLocationOrder(left, right) { return true }
        if sourceLocationOrder(right, left) { return false }
        if lhs.key.scope != rhs.key.scope { return lhs.key.scope < rhs.key.scope }
        if lhs.key.discriminator != rhs.key.discriminator {
            return lhs.key.discriminator < rhs.key.discriminator
        }
        return lhs.key.caseShape.lexicographicallyPrecedes(rhs.key.caseShape)
    }
}

private struct RepeatedSwitchKey: Hashable {
    let scope: String
    let discriminator: String
    let caseShape: [String]
}

private struct RepeatedSwitchGroup {
    let key: RepeatedSwitchKey
    let occurrences: [RepeatedSwitchUnit]
}
