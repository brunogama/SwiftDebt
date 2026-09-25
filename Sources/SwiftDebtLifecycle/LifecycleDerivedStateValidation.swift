extension LifecycleArtifact {
    func validateDerivedState(
        snapshots: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        var observedCounts: [DetectionDispositionKey: Int] = [:]
        for finding in findings {
            guard let firstEvent = finding.events.first,
                case .opened(let evidence) = firstEvent.transition,
                let openingSnapshot = snapshots[firstEvent.snapshotID]
            else {
                throw LifecycleContractError.invalidArtifact("A Finding has no opening Detection disposition.")
            }
            observedCounts[
                DetectionDispositionKey(snapshotID: firstEvent.snapshotID, detectionID: evidence.detectionID),
                default: 0
            ] += 1
            for event in finding.events.dropFirst() {
                switch event.transition {
                case .observed(let continuation), .reopened(let continuation):
                    observedCounts[
                        DetectionDispositionKey(
                            snapshotID: event.snapshotID,
                            detectionID: continuation.currentDetection.detectionID
                        ),
                        default: 0
                    ] += 1
                case .opened, .resolved, .unverified, .continuityAmbiguous:
                    break
                }
            }
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
                guard observedCounts[key, default: 0] + unresolvedCounts[key, default: 0] == 1 else {
                    throw LifecycleContractError.invalidArtifact(
                        "Detection \(detection.id) must be observed or unresolved exactly once."
                    )
                }
            }
        }
        try validateReconciliationProjection(snapshots: snapshots, processed: processed)
    }

    private func validateOpeningEligibility(
        finding: Finding,
        openingSnapshot: ObservationSnapshot,
        snapshots: [SnapshotID: ObservationSnapshot]
    ) throws {
        guard let openingDetection = openingSnapshot.detection(id: finding.openingDetectionID) else {
            throw LifecycleContractError.invalidArtifact("Finding \(finding.id) has no opening Detection.")
        }
        let openingSequence = openingSnapshot.provenance.lineage.sequence
        let priorFindings = try findings.compactMap { candidate -> Finding? in
            guard candidate.id != finding.id,
                candidate.lineageID == finding.lineageID,
                candidate.rule.identity == finding.rule.identity
            else { return nil }
            return try candidate.version(before: openingSequence, snapshots: snapshots)
        }
        guard !priorFindings.isEmpty else { return }
        let reconciliation = try ContinuityReconciler().reconcile(
            findings: priorFindings,
            detections: [openingDetection],
            snapshot: openingSnapshot,
            artifact: self
        )
        guard reconciliation.newDetections.map(\.id) == [openingDetection.id] else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) opened despite a credible continuity candidate."
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
        let eventsBySequence = try Dictionary(
            uniqueKeysWithValues: finding.events.map { event in
                guard let sequence = snapshots[event.snapshotID]?.provenance.lineage.sequence else {
                    throw LifecycleContractError.invalidArtifact("Finding \(finding.id) references a missing snapshot.")
                }
                return (sequence, event)
            })
        var state = FindingLifecycleState.open
        for sequence in firstSnapshot.provenance.lineage.sequence...head.sequence {
            let event = eventsBySequence[sequence]
            if state == .open, event == nil {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) is missing lifecycle evidence while open at sequence \(sequence)."
                )
            }
            guard let event else { continue }
            switch event.transition {
            case .opened, .observed, .unverified, .continuityAmbiguous:
                break
            case .resolved:
                state = .resolved
            case .reopened:
                state = .open
            }
        }
    }
}

extension Finding {
    func version(
        before sequence: UInt,
        snapshots: [SnapshotID: ObservationSnapshot]
    ) throws -> Finding? {
        let priorEvents = events.filter { event in
            guard let eventSequence = snapshots[event.snapshotID]?.provenance.lineage.sequence else {
                return false
            }
            return eventSequence < sequence
        }
        guard !priorEvents.isEmpty else { return nil }
        return try Finding(
            id: id,
            lineageID: lineageID,
            rule: rule,
            events: priorEvents
        )
    }
}

private struct DetectionDispositionKey: Hashable {
    let snapshotID: SnapshotID
    let detectionID: DetectionID
}
