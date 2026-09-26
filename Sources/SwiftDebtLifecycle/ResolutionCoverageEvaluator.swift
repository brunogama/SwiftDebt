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
                    message: "Capability availability changed: opening ["
                        + capabilitySummary(firstSnapshot.provenance.capabilities)
                        + "]; later [" + capabilitySummary(snapshot.provenance.capabilities) + "]."
                )
            )
        }
        if firstSnapshot.provenance.capabilities.contains(where: { !$0.state.supportsComparison })
            || snapshot.provenance.capabilities.contains(where: { !$0.state.supportsComparison })
        {
            blockers.append(
                try LifecycleReason(
                    code: "capability-unavailable",
                    message: "Required capabilities are unavailable or ambiguous: opening ["
                        + capabilitySummary(firstSnapshot.provenance.capabilities)
                        + "]; later [" + capabilitySummary(snapshot.provenance.capabilities) + "]."
                )
            )
        }

        let sameIdentityRules = snapshot.rules.filter { $0.identity == finding.rule.identity }
        let hasComparableRule = sameIdentityRules.contains(finding.rule)
        let comparable = snapshot.atomicObservations.filter { $0.rule == finding.rule }
        if !hasComparableRule {
            blockers.append(
                try LifecycleReason(
                    code: sameIdentityRules.isEmpty ? "rule-omitted" : "semantic-revision-incomparable",
                    message: sameIdentityRules.isEmpty
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
            reasons: ([
                try LifecycleReason(
                    code: "complete-comparable-absence",
                    message: "Complete repository scope committed every comparable "
                        + "Atomic Observation with zero Detections."
                )
            ] + relocation.proofReasons).sorted(by: lifecycleReasonOrder)
        )
    }

    private func capabilitySummary(_ capabilities: [SnapshotCapability]) -> String {
        guard !capabilities.isEmpty else { return "none" }
        return capabilities.map { capability in
            let state: String
            switch capability.state {
            case .available:
                state = "available"
            case .unavailable(let reason):
                state = "unavailable (\(reason.code): \(reason.message))"
            case .ambiguous(let reason):
                state = "ambiguous (\(reason.code): \(reason.message))"
            }
            return "\(capability.name)=\(state)"
        }.joined(separator: ", ")
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
