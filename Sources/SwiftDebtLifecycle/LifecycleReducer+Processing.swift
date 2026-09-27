import Dispatch

extension LifecycleReducer {
    func process(
        _ snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact,
        profiling: Bool
    ) throws -> LifecycleReconciliationProfile? {
        let processingStartedAt = profiling ? DispatchTime.now().uptimeNanoseconds : nil
        let priorFindings = try artifact.parentFindingProjections(of: snapshot.id).map(\.finding)
        var findingIndexByID = Dictionary(
            uniqueKeysWithValues: artifact.findings.enumerated().map { ($0.element.id, $0.offset) }
        )
        let identities = Set(
            priorFindings.map { $0.rule.identity }
                + snapshot.detections.map { $0.rule.identity }
        ).sorted { $0.description < $1.description }
        var candidateCount = 0
        var evaluatedPairs = 0
        var crediblePairs = 0
        var uniqueContinuities = 0
        var newFindings = 0
        var unresolvedDetections = 0
        var ambiguousGroups = 0
        var reconciliationElapsedNanoseconds: UInt64 = 0

        for identity in identities {
            let candidates = priorFindings.filter { $0.rule.identity == identity }
            let detections = snapshot.detections.filter { $0.rule.identity == identity }
            if profiling { candidateCount += candidates.count }
            if candidates.isEmpty {
                for detection in detections {
                    try openFinding(
                        for: detection,
                        snapshot: snapshot,
                        artifact: &artifact,
                        findingIndexByID: &findingIndexByID
                    )
                }
                if profiling { newFindings += detections.count }
                continue
            }
            if detections.isEmpty {
                for candidate in candidates {
                    try recordAbsence(
                        for: candidate,
                        snapshot: snapshot,
                        artifact: &artifact,
                        findingIndexByID: findingIndexByID
                    )
                }
                continue
            }

            let startedAt = profiling ? DispatchTime.now().uptimeNanoseconds : nil
            let reconciliation = try ContinuityReconciler().reconcile(
                findings: candidates,
                detections: detections,
                snapshot: snapshot,
                artifact: artifact
            )
            if let startedAt {
                reconciliationElapsedNanoseconds += DispatchTime.now().uptimeNanoseconds - startedAt
                evaluatedPairs += reconciliation.evaluatedPairs
                crediblePairs += reconciliation.crediblePairs
                uniqueContinuities += reconciliation.matches.count
                newFindings += reconciliation.newDetections.count
                unresolvedDetections += reconciliation.unresolvedGroups.reduce(0) { $0 + $1.detections.count }
                ambiguousGroups += reconciliation.unresolvedGroups.filter(\.isAmbiguous).count
            }
            for match in reconciliation.matches {
                try record(
                    match: match,
                    snapshot: snapshot,
                    artifact: &artifact,
                    findingIndexByID: findingIndexByID
                )
            }
            for group in reconciliation.unresolvedGroups {
                try record(
                    group: group,
                    snapshot: snapshot,
                    artifact: &artifact,
                    findingIndexByID: findingIndexByID
                )
            }
            for detection in reconciliation.newDetections {
                try openFinding(
                    for: detection,
                    snapshot: snapshot,
                    artifact: &artifact,
                    findingIndexByID: &findingIndexByID
                )
            }
            for finding in reconciliation.absentFindings {
                try recordAbsence(
                    for: finding,
                    snapshot: snapshot,
                    artifact: &artifact,
                    findingIndexByID: findingIndexByID
                )
            }
        }
        guard let processingStartedAt else { return nil }
        return LifecycleReconciliationProfile(
            snapshotID: snapshot.id,
            detections: snapshot.detections.count,
            candidates: candidateCount,
            evaluatedPairs: evaluatedPairs,
            crediblePairs: crediblePairs,
            uniqueContinuities: uniqueContinuities,
            newFindings: newFindings,
            unresolvedDetections: unresolvedDetections,
            ambiguousGroups: ambiguousGroups,
            processingElapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - processingStartedAt,
            reconciliationElapsedNanoseconds: reconciliationElapsedNanoseconds
        )
    }

}
