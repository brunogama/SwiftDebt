import SwiftDebtCore

extension IntroductionConclusionEvaluator {
    func trace(
        _ revision: GitRevisionID,
        records: [GitRevisionID: IntroductionHistoryRevision],
        frontier: Set<GitRevisionID>,
        openingDetection: ObservedDetection,
        openingSnapshot: ObservationSnapshot,
        rule: SnapshotRule,
        visited: Set<GitRevisionID>
    ) throws -> TraceResult {
        guard !visited.contains(revision), let record = records[revision] else {
            return try bounded(
                at: revision,
                code: "history-ancestry-incomplete",
                message: "The positive history path is cyclic or missing from the captured boundary."
            )
        }
        var visited = visited
        visited.insert(revision)
        guard !record.parentRevisions.isEmpty else {
            return TraceResult(
                kind: .exact,
                exactRevision: revision,
                earliestPositiveRevision: revision,
                reasons: [
                    try LifecycleReason(
                        code: "verified-repository-root",
                        message: "The comparable positive revision is a verified repository root."
                    )
                ],
                semanticComparisons: []
            )
        }

        var positiveParents: [GitRevisionID] = []
        var blockers: [LifecycleReason] = []
        var semanticComparisons: [SemanticComparisonBasis] = []
        for parent in record.parentRevisions {
            guard let parentRecord = records[parent] else {
                let code = frontier.contains(parent) ? "history-budget-exhausted" : "history-parent-missing"
                blockers.append(
                    try LifecycleReason(
                        code: code,
                        message: "Parent revision \(parent.rawValue) was not analyzed within this history boundary."
                    )
                )
                continue
            }
            switch try assess(
                parentRecord,
                openingDetection: openingDetection,
                openingSnapshot: openingSnapshot,
                rule: rule
            ) {
            case .present(let comparison):
                positiveParents.append(parent)
                semanticComparisons.append(comparison)
            case .absent(let comparison):
                semanticComparisons.append(comparison)
                continue
            case .incomplete(let reasons, let comparisons):
                blockers += reasons
                semanticComparisons += comparisons
            }
        }
        if !blockers.isEmpty {
            return TraceResult(
                kind: .bounded,
                exactRevision: nil,
                earliestPositiveRevision: revision,
                reasons: unique(blockers),
                semanticComparisons: uniqueSemanticComparisons(semanticComparisons)
            )
        }
        if positiveParents.isEmpty {
            return TraceResult(
                kind: .exact,
                exactRevision: revision,
                earliestPositiveRevision: revision,
                reasons: [
                    try LifecycleReason(
                        code: "verified-parent-absence",
                        message:
                            "The Finding is present at \(revision.rawValue) and absent from every comparable parent."
                    )
                ],
                semanticComparisons: uniqueSemanticComparisons(semanticComparisons)
            )
        }
        guard positiveParents.count == 1, let positiveParent = positiveParents.first else {
            var result = try bounded(
                at: revision,
                code: "multiple-positive-parent-lineages",
                message:
                    "More than one parent contains the Finding, so this boundary does not identify one introduction path."
            )
            result.semanticComparisons = uniqueSemanticComparisons(semanticComparisons)
            return result
        }
        var result = try trace(
            positiveParent,
            records: records,
            frontier: frontier,
            openingDetection: openingDetection,
            openingSnapshot: openingSnapshot,
            rule: rule,
            visited: visited
        )
        result.reasons.append(
            try LifecycleReason(
                code: "positive-parent-followed",
                message: "Revision \(revision.rawValue) continues the Finding from parent \(positiveParent.rawValue)."
            )
        )
        result.reasons = unique(result.reasons)
        result.semanticComparisons = uniqueSemanticComparisons(
            result.semanticComparisons + semanticComparisons
        )
        return result
    }

    func bounded(at revision: GitRevisionID, code: String, message: String) throws -> TraceResult {
        TraceResult(
            kind: .bounded,
            exactRevision: nil,
            earliestPositiveRevision: revision,
            reasons: [try LifecycleReason(code: code, message: message)],
            semanticComparisons: []
        )
    }

    func gitRevision(of snapshot: ObservationSnapshot) -> GitRevisionID? {
        guard case .git(let revision, _, _) = snapshot.provenance.sourceIdentity else { return nil }
        return revision
    }

    func sourceDigest(of snapshot: ObservationSnapshot) -> LifecycleDigest? {
        switch snapshot.provenance.sourceIdentity {
        case .git(_, _, let digest), .contentDigest(let digest): digest
        case .unavailable: nil
        }
    }

    func unique(_ reasons: [LifecycleReason]) -> [LifecycleReason] {
        Array(Set(reasons)).sorted(by: lifecycleReasonOrder)
    }
}
