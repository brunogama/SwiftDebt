extension LifecycleReducer {
    func process(_ snapshot: ObservationSnapshot, artifact: inout LifecycleArtifact) throws {
        let lineageID = snapshot.provenance.lineage.lineageID
        let priorFindings = artifact.findings.filter { $0.lineageID == lineageID }
        let identities = Set(
            priorFindings.map { $0.rule.identity }
                + snapshot.detections.map { $0.rule.identity }
        ).sorted { $0.description < $1.description }

        for identity in identities {
            let candidates = priorFindings.filter { $0.rule.identity == identity }
            let currentDetections = snapshot.detections.filter { $0.rule.identity == identity }
            if candidates.isEmpty {
                for detection in currentDetections {
                    try openFinding(for: detection, snapshot: snapshot, artifact: &artifact)
                }
                continue
            }
            if currentDetections.isEmpty {
                for candidate in candidates {
                    try recordAbsence(for: candidate, snapshot: snapshot, artifact: &artifact)
                }
                continue
            }
            try recordUnresolvedContinuity(
                candidates: candidates,
                detections: currentDetections,
                snapshot: snapshot,
                artifact: &artifact
            )
        }
    }

    private func openFinding(
        for detection: ObservedDetection,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact
    ) throws {
        guard let atomic = snapshot.atomicObservations.first(where: { $0.outcome.references(detection.id) }) else {
            throw LifecycleContractError.invalidSnapshot("Detection \(detection.id) has no Atomic Observation.")
        }
        let findingID = try FindingID("finding:\(snapshot.id.rawValue):\(detection.id.rawValue)")
        let event = LifecycleEvent(
            id: try LifecycleEventID("event:\(findingID.rawValue):opened"),
            snapshotID: snapshot.id,
            transition: .opened(
                DetectionEvidence(detectionID: detection.id, atomicObservationID: atomic.id)
            )
        )
        artifact.findings.append(
            try Finding(
                id: findingID,
                lineageID: snapshot.provenance.lineage.lineageID,
                rule: detection.rule,
                events: [event]
            )
        )
    }

    private func recordUnresolvedContinuity(
        candidates: [Finding],
        detections: [ObservedDetection],
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact
    ) throws {
        let candidateIDs = candidates.map(\.id).sorted { $0.rawValue < $1.rawValue }
        let detectionIDs = detections.map(\.id).sorted { $0.rawValue < $1.rawValue }
        let sameRevisionExists = candidates.contains { candidate in
            detections.contains { $0.rule.semanticRevision == candidate.rule.semanticRevision }
        }
        let reason = try LifecycleReason(
            code: sameRevisionExists ? "continuity-evidence-unavailable" : "semantic-revision-incomparable",
            message: sameRevisionExists
                ? "R1 Detection has no engine-owned structural identity evidence, so no predecessor was selected."
                : "The current and prior Semantic Revisions have no compatibility declaration."
        )

        for candidate in candidates {
            guard let index = artifact.findings.firstIndex(where: { $0.id == candidate.id }) else { continue }
            let transition: LifecycleTransition
            if detections.contains(where: { $0.rule.semanticRevision == candidate.rule.semanticRevision }) {
                transition = .continuityAmbiguous(
                    ContinuityAmbiguityEvidence(
                        currentDetectionIDs: detectionIDs,
                        candidateFindingIDs: candidateIDs,
                        reasons: [reason]
                    )
                )
            } else {
                transition = .unverified([reason])
            }
            try artifact.findings[index].append(
                LifecycleEvent(
                    id: try eventID(findingID: candidate.id, snapshotID: snapshot.id, kind: transition.kind),
                    snapshotID: snapshot.id,
                    transition: transition
                )
            )
        }
        for detection in detections {
            artifact.unresolvedDetections.append(
                UnresolvedDetection(
                    snapshotID: snapshot.id,
                    detectionID: detection.id,
                    candidateFindingIDs: candidateIDs,
                    reasons: [reason]
                )
            )
        }
    }

    private func recordAbsence(
        for finding: Finding,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact
    ) throws {
        let assessment = try ResolutionCoverageEvaluator().assess(
            finding: finding,
            snapshot: snapshot,
            artifact: artifact
        )
        guard let index = artifact.findings.firstIndex(where: { $0.id == finding.id }) else { return }
        switch assessment {
        case .verified(let atomicObservationIDs, let reasons):
            guard finding.lifecycleState == .open else { return }
            let transition = LifecycleTransition.resolved(
                ResolutionEvidence(
                    priorSnapshotID: finding.firstObservationSnapshotID,
                    coveredAtomicObservationIDs: atomicObservationIDs,
                    reasons: reasons
                )
            )
            try artifact.findings[index].append(
                LifecycleEvent(
                    id: try eventID(findingID: finding.id, snapshotID: snapshot.id, kind: transition.kind),
                    snapshotID: snapshot.id,
                    transition: transition
                )
            )
        case .unverified(let reasons):
            let transition = LifecycleTransition.unverified(reasons)
            try artifact.findings[index].append(
                LifecycleEvent(
                    id: try eventID(findingID: finding.id, snapshotID: snapshot.id, kind: transition.kind),
                    snapshotID: snapshot.id,
                    transition: transition
                )
            )
        }
    }

    private func eventID(
        findingID: FindingID,
        snapshotID: SnapshotID,
        kind: LifecycleTransition.Kind
    ) throws -> LifecycleEventID {
        try LifecycleEventID("event:\(findingID.rawValue):\(snapshotID.rawValue):\(kind.rawValue)")
    }
}
