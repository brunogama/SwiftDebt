extension LifecycleReducer {
    func process(_ snapshot: ObservationSnapshot, artifact: inout LifecycleArtifact) throws {
        let priorFindings = try artifact.parentFindingProjections(of: snapshot.id).map(\.finding)
        let identities = Set(
            priorFindings.map { $0.rule.identity }
                + snapshot.detections.map { $0.rule.identity }
        ).sorted { $0.description < $1.description }

        for identity in identities {
            let candidates = priorFindings.filter { $0.rule.identity == identity }
            let detections = snapshot.detections.filter { $0.rule.identity == identity }
            if candidates.isEmpty {
                for detection in detections {
                    try openFinding(for: detection, snapshot: snapshot, artifact: &artifact)
                }
                continue
            }
            if detections.isEmpty {
                for candidate in candidates {
                    try recordAbsence(for: candidate, snapshot: snapshot, artifact: &artifact)
                }
                continue
            }

            let reconciliation = try ContinuityReconciler().reconcile(
                findings: candidates,
                detections: detections,
                snapshot: snapshot,
                artifact: artifact
            )
            for match in reconciliation.matches {
                try record(match: match, snapshot: snapshot, artifact: &artifact)
            }
            for group in reconciliation.unresolvedGroups {
                try record(group: group, snapshot: snapshot, artifact: &artifact)
            }
            for detection in reconciliation.newDetections {
                try openFinding(for: detection, snapshot: snapshot, artifact: &artifact)
            }
            for finding in reconciliation.absentFindings {
                try recordAbsence(for: finding, snapshot: snapshot, artifact: &artifact)
            }
        }
    }

    private func openFinding(
        for detection: ObservedDetection,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact
    ) throws {
        let evidence = try detectionEvidence(for: detection, snapshot: snapshot)
        let findingID = try FindingID("finding:\(snapshot.id.rawValue):\(detection.id.rawValue)")
        let event = LifecycleEvent(
            id: try LifecycleEventID("event:\(findingID.rawValue):opened"),
            snapshotID: snapshot.id,
            basisEventIDs: [],
            transition: .opened(evidence)
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

    private func record(
        match: ContinuityMatch,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact
    ) throws {
        guard let index = artifact.findings.firstIndex(where: { $0.id == match.finding.id }),
            let basisEventID = match.finding.events.last?.id
        else {
            return
        }
        let evidence = MatchedContinuityEvidence(
            currentDetection: try detectionEvidence(for: match.currentDetection, snapshot: snapshot),
            priorSnapshotID: match.priorSnapshot.id,
            priorDetectionID: match.priorDetection.id,
            reasons: match.reasons
        )
        let transition: LifecycleTransition =
            match.finding.lifecycleState == .resolved ? .reopened(evidence) : .observed(evidence)
        try artifact.findings[index].append(
            LifecycleEvent(
                id: try eventID(
                    findingID: match.finding.id,
                    snapshotID: snapshot.id,
                    kind: transition.kind
                ),
                snapshotID: snapshot.id,
                basisEventIDs: [basisEventID],
                transition: transition
            )
        )
    }

    private func record(
        group: ContinuityUnresolvedGroup,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact
    ) throws {
        let candidateIDs = group.findings.map(\.id)
        let detectionIDs = group.detections.map(\.id)
        for finding in group.findings {
            guard finding.lifecycleState == .open else { continue }
            guard let index = artifact.findings.firstIndex(where: { $0.id == finding.id }),
                let basisEventID = finding.events.last?.id
            else { continue }
            let transition: LifecycleTransition =
                group.isAmbiguous
                ? .continuityAmbiguous(
                    ContinuityAmbiguityEvidence(
                        currentDetectionIDs: detectionIDs,
                        candidateFindingIDs: candidateIDs,
                        reasons: group.reasons
                    )
                )
                : .unverified(group.reasons)
            try artifact.findings[index].append(
                LifecycleEvent(
                    id: try eventID(
                        findingID: finding.id,
                        snapshotID: snapshot.id,
                        kind: transition.kind
                    ),
                    snapshotID: snapshot.id,
                    basisEventIDs: [basisEventID],
                    transition: transition
                )
            )
        }
        for detection in group.detections {
            artifact.unresolvedDetections.append(
                UnresolvedDetection(
                    snapshotID: snapshot.id,
                    detectionID: detection.id,
                    candidateFindingIDs: candidateIDs,
                    reasons: group.reasons
                )
            )
        }
    }

    private func detectionEvidence(
        for detection: ObservedDetection,
        snapshot: ObservationSnapshot
    ) throws -> DetectionEvidence {
        guard let atomic = snapshot.atomicObservations.first(where: { $0.outcome.references(detection.id) }) else {
            throw LifecycleContractError.invalidSnapshot("Detection \(detection.id) has no Atomic Observation.")
        }
        return DetectionEvidence(detectionID: detection.id, atomicObservationID: atomic.id)
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
        guard let index = artifact.findings.firstIndex(where: { $0.id == finding.id }),
            let basisEventID = finding.events.last?.id
        else { return }
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
                    basisEventIDs: [basisEventID],
                    transition: transition
                )
            )
        case .unverified(let reasons):
            guard finding.lifecycleState == .open else { return }
            let transition = LifecycleTransition.unverified(reasons)
            try artifact.findings[index].append(
                LifecycleEvent(
                    id: try eventID(findingID: finding.id, snapshotID: snapshot.id, kind: transition.kind),
                    snapshotID: snapshot.id,
                    basisEventIDs: [basisEventID],
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
