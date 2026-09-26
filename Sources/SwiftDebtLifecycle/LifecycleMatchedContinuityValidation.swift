extension LifecycleArtifact {
    func validateMatchedContinuity(
        _ evidence: MatchedContinuityEvidence,
        finding: Finding,
        snapshot: ObservationSnapshot
    ) throws {
        guard let currentDetection = snapshot.detection(id: evidence.currentDetection.detectionID),
            let currentAtomic = snapshot.atomicObservation(id: evidence.currentDetection.atomicObservationID),
            currentDetection.rule == finding.rule,
            currentAtomic.rule == finding.rule,
            currentAtomic.sourcePath == currentDetection.location.sourcePath,
            currentAtomic.outcome.references(currentDetection.id),
            let eventIndex = finding.events.firstIndex(where: { $0.snapshotID == snapshot.id }),
            let priorReference = priorDetectionReference(
                in: finding.events[..<eventIndex]
            ),
            priorReference.snapshotID == evidence.priorSnapshotID,
            priorReference.detectionID == evidence.priorDetectionID,
            let priorSnapshot = self.snapshot(id: evidence.priorSnapshotID),
            let priorDetection = priorSnapshot.detection(id: evidence.priorDetectionID)
        else {
            throw LifecycleContractError.invalidArtifact(
                "An observed or reopened event has broken Detection evidence."
            )
        }
        let candidate = Candidate(
            finding: finding,
            snapshot: priorSnapshot,
            detection: priorDetection
        )
        let relation = try ContinuityReconciler().relation(
            candidate: candidate,
            detection: currentDetection,
            snapshot: snapshot
        )
        guard case .supported(let expectedReasons) = relation,
            evidence.reasons == expectedReasons.sorted(by: lifecycleReasonOrder)
        else {
            throw LifecycleContractError.invalidArtifact(
                "An observed or reopened event lacks sufficient structural continuity evidence."
            )
        }

        let priorFindings = try parentFindingProjections(of: snapshot.id).compactMap { projection in
            let candidate = projection.finding
            return candidate.rule.identity == finding.rule.identity ? candidate : nil
        }
        let currentDetections = snapshot.detections.filter {
            $0.rule.identity == finding.rule.identity
        }
        let reconciliation = try ContinuityReconciler().reconcile(
            findings: priorFindings,
            detections: currentDetections,
            snapshot: snapshot,
            artifact: self
        )
        guard
            reconciliation.matches.contains(where: {
                $0.finding.id == finding.id
                    && $0.priorSnapshot.id == evidence.priorSnapshotID
                    && $0.priorDetection.id == evidence.priorDetectionID
                    && $0.currentDetection.id == evidence.currentDetection.detectionID
            })
        else {
            throw LifecycleContractError.invalidArtifact(
                "An observed or reopened event does not have one unique structural assignment."
            )
        }
    }

    private func priorDetectionReference(
        in events: ArraySlice<LifecycleEvent>
    ) -> (snapshotID: SnapshotID, detectionID: DetectionID)? {
        for event in events.reversed() {
            switch event.transition {
            case .opened(let evidence):
                return (event.snapshotID, evidence.detectionID)
            case .observed(let evidence), .reopened(let evidence):
                return (event.snapshotID, evidence.currentDetection.detectionID)
            case .resolved, .unverified, .continuityAmbiguous:
                continue
            }
        }
        return nil
    }
}
