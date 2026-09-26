extension LifecycleArtifact {
    func validateDerivedState(
        snapshots: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        var observedCounts: [DetectionDispositionKey: Int] = [:]
        for finding in findings {
            let firstEvent = finding.openingEvent
            guard case .opened(let evidence) = firstEvent.transition,
                let openingSnapshot = snapshots[firstEvent.snapshotID]
            else {
                throw LifecycleContractError.invalidArtifact("A Finding has no opening Detection disposition.")
            }
            observedCounts[
                DetectionDispositionKey(snapshotID: firstEvent.snapshotID, detectionID: evidence.detectionID),
                default: 0
            ] += 1
            for event in finding.events where event.id != firstEvent.id {
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
                openingSnapshot: openingSnapshot
            )
            try validateRequiredEventCoverage(finding: finding)
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
        openingSnapshot: ObservationSnapshot
    ) throws {
        guard let openingDetection = openingSnapshot.detection(id: finding.openingDetectionID) else {
            throw LifecycleContractError.invalidArtifact("Finding \(finding.id) has no opening Detection.")
        }
        let priorFindings = try parentFindingProjections(of: openingSnapshot.id).compactMap { projection in
            let candidate = projection.finding
            return candidate.rule.identity == finding.rule.identity ? candidate : nil
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

    private func validateRequiredEventCoverage(finding: Finding) throws {
        for headID in headSnapshotIDs {
            guard let projection = try findingProjection(finding, at: headID) else { continue }
            let path = try snapshotPath(through: headID)
            guard
                let openingIndex = path.firstIndex(where: {
                    $0.id == projection.finding.firstObservationSnapshotID
                })
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) projection does not contain its First Observation."
                )
            }
            let eventsBySnapshot = Dictionary(
                uniqueKeysWithValues: projection.finding.events.map { ($0.snapshotID, $0) }
            )
            var state = FindingLifecycleState.open
            for snapshot in path[openingIndex...] {
                let event = eventsBySnapshot[snapshot.id]
                if state == .open, event == nil {
                    throw LifecycleContractError.invalidArtifact(
                        "Finding \(finding.id) is missing lifecycle evidence while open at snapshot \(snapshot.id)."
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
}

private struct DetectionDispositionKey: Hashable {
    let snapshotID: SnapshotID
    let detectionID: DetectionID
}
