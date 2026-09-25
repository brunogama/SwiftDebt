enum ResolutionCoverageAssessment {
    case verified(atomicObservationIDs: [AtomicObservationID], reasons: [LifecycleReason])
    case unverified([LifecycleReason])
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

        var blockers: [LifecycleReason] = []
        try requireOrderedSuccessor(
            firstSnapshot: firstSnapshot,
            currentSnapshot: snapshot,
            finding: finding,
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
        if !firstSnapshot.provenance.sourceIdentity.supportsComparison
            || !snapshot.provenance.sourceIdentity.supportsComparison
        {
            blockers.append(
                try LifecycleReason(
                    code: "source-identity-unavailable",
                    message: "Comparable source identity is unavailable for one or both snapshots."
                )
            )
        }
        if snapshot.provenance.configurationFingerprint != firstSnapshot.provenance.configurationFingerprint {
            blockers.append(
                try LifecycleReason(
                    code: "configuration-incomparable",
                    message: "The effective configuration fingerprint changed."
                )
            )
        }
        if snapshot.provenance.engineVersion != firstSnapshot.provenance.engineVersion {
            blockers.append(
                try LifecycleReason(
                    code: "engine-incomparable",
                    message: "The analysis engine version changed without a compatibility declaration."
                )
            )
        }
        if snapshot.provenance.capabilities != firstSnapshot.provenance.capabilities {
            blockers.append(
                try LifecycleReason(
                    code: "capabilities-incomparable",
                    message: "The capability availability set changed."
                )
            )
        }
        if firstSnapshot.provenance.capabilities.contains(where: { !$0.state.supportsComparison })
            || snapshot.provenance.capabilities.contains(where: { !$0.state.supportsComparison })
        {
            blockers.append(
                try LifecycleReason(
                    code: "capability-unavailable",
                    message: "A required capability is unavailable or ambiguous."
                )
            )
        }

        let sameIdentity = snapshot.atomicObservations.filter { $0.rule.identity == finding.rule.identity }
        let comparable = sameIdentity.filter { $0.rule == finding.rule }
        if comparable.isEmpty {
            blockers.append(
                try LifecycleReason(
                    code: sameIdentity.isEmpty ? "rule-omitted" : "semantic-revision-incomparable",
                    message: sameIdentity.isEmpty
                        ? "The later snapshot omitted the Finding's rule."
                        : "The later snapshot has no compatible Semantic Revision."
                )
            )
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
            return .unverified(blockers.sorted(by: lifecycleReasonOrder))
        }
        return .verified(
            atomicObservationIDs: comparable.map(\.id).sorted { $0.rawValue < $1.rawValue },
            reasons: [
                try LifecycleReason(
                    code: "complete-comparable-absence",
                    message: "Complete repository scope committed every comparable "
                        + "Atomic Observation with zero Detections."
                )
            ]
        )
    }

    private func requireOrderedSuccessor(
        firstSnapshot: ObservationSnapshot,
        currentSnapshot: ObservationSnapshot,
        finding: Finding,
        blockers: inout [LifecycleReason]
    ) throws {
        let first = firstSnapshot.provenance.lineage
        let current = currentSnapshot.provenance.lineage
        guard first.lineageID == finding.lineageID,
            current.lineageID == finding.lineageID,
            current.sequence > first.sequence
        else {
            blockers.append(
                try LifecycleReason(
                    code: "lineage-incomparable",
                    message: "Verified absence requires a later snapshot in the Finding's lineage."
                )
            )
            return
        }
    }
}
