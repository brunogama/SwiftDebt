enum ResolutionCoverageAssessment {
    case verified(
        atomicObservationIDs: [AtomicObservationID],
        reasons: [LifecycleReason],
        semanticComparisons: [SemanticComparisonBasis]
    )
    case unverified([LifecycleReason], semanticComparisons: [SemanticComparisonBasis])
}

struct ResolutionCoverageEvaluator {
    func assess(
        finding: Finding,
        snapshot: ObservationSnapshot,
        artifact: LifecycleArtifact
    ) throws -> ResolutionCoverageAssessment {
        guard let firstSnapshot = artifact.snapshot(id: finding.firstObservationSnapshotID) else {
            throw LifecycleContractError.invalidArtifact("Finding \(finding.id) has no first snapshot.")
        }
        let priorReference = finding.latestDetectionReference
        guard let priorSnapshot = artifact.snapshot(id: priorReference.snapshotID),
            let priorDetection = priorSnapshot.detection(id: priorReference.detectionID)
        else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) has no latest Detection evidence."
            )
        }

        var blockers: [LifecycleReason] = []
        var proofReasons: [LifecycleReason] = []
        var semanticComparisons: [SemanticComparisonBasis] = []
        try requireOrderedSuccessor(
            firstSnapshot: firstSnapshot,
            currentSnapshot: snapshot,
            finding: finding,
            artifact: artifact,
            blockers: &blockers
        )
        if !snapshot.provenance.scope.isCompleteRepository {
            blockers.append(
                try LifecycleReason(
                    code: "scope-incomplete",
                    message: "The later snapshot does not cover the complete repository relocation scope."
                )
            )
        }
        let relocation = try assessRelocation(
            finding: finding,
            snapshot: snapshot,
            artifact: artifact
        )
        blockers += relocation.blockers
        let sameIdentityRules = snapshot.rules.filter { $0.identity == finding.rule.identity }
        let currentRule = sameIdentityRules.first
        let comparable: [AtomicObservation]
        if let currentRule {
            let comparison = try SemanticComparisonEvaluator().assess(
                claim: .absence,
                priorSnapshot: priorSnapshot,
                priorRule: priorDetection.rule,
                currentSnapshot: snapshot,
                currentRule: currentRule
            )
            semanticComparisons = [comparison.basis]
            if comparison.isCompatible {
                proofReasons += comparison.reasons
            } else {
                blockers += comparison.reasons
            }
            comparable = snapshot.atomicObservations.filter { $0.rule == currentRule }
        } else {
            blockers.append(
                try LifecycleReason(
                    code: "rule-omitted",
                    message: "The later snapshot omitted the Finding's rule."
                )
            )
            comparable = []
        }
        for observation in comparable where !observation.outcome.provesAbsence {
            blockers.append(
                try LifecycleReason(
                    code: "atomic-observation-\(observation.outcome.kind.rawValue)",
                    message: "\(observation.rule.identity) did not prove absence for "
                        + "\(observation.sourcePath.rawValue)."
                )
            )
        }
        if snapshot.detections.contains(where: { $0.rule.identity == finding.rule.identity }) {
            blockers.append(
                try LifecycleReason(
                    code: "continuity-candidate-present",
                    message: "The resolving snapshot contains a Detection with the same Rule Identity."
                )
            )
        }
        if artifact.unresolvedDetections.contains(where: {
            $0.snapshotID == snapshot.id && $0.candidateFindingIDs.contains(finding.id)
        }) {
            blockers.append(
                try LifecycleReason(
                    code: "continuity-unresolved",
                    message: "The resolving snapshot retains an Unresolved Detection for this Finding."
                )
            )
        }

        guard blockers.isEmpty else {
            return .unverified(
                Array(Set(blockers)).sorted(by: lifecycleReasonOrder),
                semanticComparisons: semanticComparisons
            )
        }
        return .verified(
            atomicObservationIDs: comparable.map(\.id).sorted { $0.rawValue < $1.rawValue },
            reasons: Array(
                Set(
                    [
                        try LifecycleReason(
                            code: "complete-comparable-absence",
                            message: "Complete repository scope committed every comparable "
                                + "Atomic Observation with zero Detections."
                        )
                    ] + relocation.proofReasons + proofReasons
                )
            ).sorted(by: lifecycleReasonOrder),
            semanticComparisons: semanticComparisons
        )
    }

    private func requireOrderedSuccessor(
        firstSnapshot: ObservationSnapshot,
        currentSnapshot: ObservationSnapshot,
        finding: Finding,
        artifact: LifecycleArtifact,
        blockers: inout [LifecycleReason]
    ) throws {
        guard firstSnapshot.id == finding.firstObservationSnapshotID,
            firstSnapshot.id != currentSnapshot.id,
            artifact.isAncestor(firstSnapshot.id, of: currentSnapshot.id)
        else {
            blockers.append(
                try LifecycleReason(
                    code: "lineage-incomparable",
                    message: "Verified absence requires a later snapshot on the selected snapshot-graph path."
                )
            )
            return
        }
    }
}
