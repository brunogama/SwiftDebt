extension LifecycleReducer {
    func openFinding(
        for detection: ObservedDetection,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact,
        findingIndexByID: inout [FindingID: Int]
    ) throws {
        let evidence = try detectionEvidence(for: detection, snapshot: snapshot)
        let findingID = try FindingID("finding:\(snapshot.id.rawValue):\(detection.id.rawValue)")
        let event = LifecycleEvent(
            id: try LifecycleEventID("event:\(findingID.rawValue):opened"),
            snapshotID: snapshot.id,
            basisEventIDs: [],
            transition: .opened(evidence)
        )
        let index = artifact.findings.count
        artifact.findings.append(
            try Finding(
                id: findingID,
                lineageID: snapshot.provenance.lineage.lineageID,
                rule: detection.rule,
                events: [event]
            )
        )
        findingIndexByID[findingID] = index
    }

    func record(
        match: ContinuityMatch,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact,
        findingIndexByID: [FindingID: Int]
    ) throws {
        guard let index = findingIndexByID[match.finding.id],
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
                transition: transition,
                semanticComparisons: [match.semanticComparison]
            )
        )
    }

    func record(
        group: ContinuityUnresolvedGroup,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact,
        findingIndexByID: [FindingID: Int]
    ) throws {
        let candidateIDs = group.findings.map(\.id)
        let detectionIDs = group.detections.map(\.id)
        for finding in group.findings {
            guard finding.lifecycleState == .open else { continue }
            guard let index = findingIndexByID[finding.id],
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
                    transition: transition,
                    semanticComparisons: group.semanticComparisons
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

    func recordAbsence(
        for finding: Finding,
        snapshot: ObservationSnapshot,
        artifact: inout LifecycleArtifact,
        findingIndexByID: [FindingID: Int]
    ) throws {
        let assessment = try ResolutionCoverageEvaluator().assess(
            finding: finding,
            snapshot: snapshot,
            artifact: artifact
        )
        guard let index = findingIndexByID[finding.id],
            let basisEventID = finding.events.last?.id
        else { return }
        switch assessment {
        case .verified(let atomicObservationIDs, let reasons, let semanticComparisons):
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
                    transition: transition,
                    semanticComparisons: semanticComparisons
                )
            )
        case .unverified(let reasons, let semanticComparisons):
            guard finding.lifecycleState == .open else { return }
            let transition = LifecycleTransition.unverified(reasons)
            try artifact.findings[index].append(
                LifecycleEvent(
                    id: try eventID(findingID: finding.id, snapshotID: snapshot.id, kind: transition.kind),
                    snapshotID: snapshot.id,
                    basisEventIDs: [basisEventID],
                    transition: transition,
                    semanticComparisons: semanticComparisons
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
