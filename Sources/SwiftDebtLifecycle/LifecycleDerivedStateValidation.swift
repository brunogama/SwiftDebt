extension LifecycleArtifact {
    func validateDerivedState(
        snapshots: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        var openingCounts: [DetectionDispositionKey: Int] = [:]
        for finding in findings {
            guard let firstEvent = finding.events.first,
                case .opened(let evidence) = firstEvent.transition,
                let openingSnapshot = snapshots[firstEvent.snapshotID]
            else {
                throw LifecycleContractError.invalidArtifact("A Finding has no opening Detection disposition.")
            }
            let key = DetectionDispositionKey(snapshotID: firstEvent.snapshotID, detectionID: evidence.detectionID)
            openingCounts[key, default: 0] += 1
            try validateOpeningEligibility(
                finding: finding,
                openingSnapshot: openingSnapshot,
                snapshots: snapshots
            )
            try validateRequiredEventCoverage(finding: finding, snapshots: snapshots)
        }

        var unresolvedCounts: [DetectionDispositionKey: Int] = [:]
        for unresolved in unresolvedDetections {
            let key = DetectionDispositionKey(
                snapshotID: unresolved.snapshotID,
                detectionID: unresolved.detectionID
            )
            unresolvedCounts[key, default: 0] += 1
        }

        for snapshotID in processed {
            guard let snapshot = snapshots[snapshotID] else { continue }
            for detection in snapshot.detections {
                let key = DetectionDispositionKey(snapshotID: snapshotID, detectionID: detection.id)
                guard openingCounts[key, default: 0] + unresolvedCounts[key, default: 0] == 1 else {
                    throw LifecycleContractError.invalidArtifact(
                        "Detection \(detection.id) must be opened or unresolved exactly once."
                    )
                }
            }
        }
    }

    private func validateOpeningEligibility(
        finding: Finding,
        openingSnapshot: ObservationSnapshot,
        snapshots: [SnapshotID: ObservationSnapshot]
    ) throws {
        let openingSequence = openingSnapshot.provenance.lineage.sequence
        let hasEarlierCandidate = findings.contains { candidate in
            guard candidate.id != finding.id,
                candidate.lineageID == finding.lineageID,
                candidate.rule.identity == finding.rule.identity,
                let candidateSnapshot = snapshots[candidate.firstObservationSnapshotID]
            else { return false }
            return candidateSnapshot.provenance.lineage.sequence < openingSequence
        }
        guard !hasEarlierCandidate else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) opened despite an earlier continuity candidate."
            )
        }
    }

    private func validateRequiredEventCoverage(
        finding: Finding,
        snapshots: [SnapshotID: ObservationSnapshot]
    ) throws {
        guard let firstSnapshot = snapshots[finding.firstObservationSnapshotID],
            let head = lineageHeads.first(where: { $0.lineageID == finding.lineageID })
        else {
            throw LifecycleContractError.invalidArtifact("Finding \(finding.id) has no processed lineage head.")
        }
        let firstSequence = firstSnapshot.provenance.lineage.sequence
        let resolvedSequence = finding.events.first(where: {
            if case .resolved = $0.transition { return true }
            return false
        }).flatMap { snapshots[$0.snapshotID]?.provenance.lineage.sequence }
        let requiredEnd = resolvedSequence ?? head.sequence
        let actual = Set(
            finding.events.compactMap { event -> UInt? in
                guard let sequence = snapshots[event.snapshotID]?.provenance.lineage.sequence,
                    sequence <= requiredEnd
                else { return nil }
                return sequence
            }
        )
        let expected = Set(firstSequence...requiredEnd)
        guard actual == expected else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) is missing required lifecycle events before resolution."
            )
        }
    }
}

private struct DetectionDispositionKey: Hashable {
    let snapshotID: SnapshotID
    let detectionID: DetectionID
}
