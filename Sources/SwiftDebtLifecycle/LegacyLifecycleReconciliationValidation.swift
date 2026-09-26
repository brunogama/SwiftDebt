extension LifecycleArtifact {
    func validateLegacyReconciliationProjection(
        snapshots: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        for snapshotID in processed where legacyProcessedSnapshotIDs.contains(snapshotID) {
            guard let snapshot = snapshots[snapshotID] else { continue }
            let priorFindings = try parentFindingProjections(of: snapshotID).map(\.finding)
            let identities = Set(
                priorFindings.map { $0.rule.identity }
                    + snapshot.detections.map { $0.rule.identity }
            )
            for identity in identities {
                let candidates = priorFindings.filter { $0.rule.identity == identity }
                let detections = snapshot.detections.filter { $0.rule.identity == identity }
                guard !detections.isEmpty else { continue }
                if candidates.isEmpty {
                    for detection in detections {
                        try legacyRequireOpening(of: detection, snapshotID: snapshot.id)
                    }
                    continue
                }
                let reconciliation = try LegacyContinuityReconciler().reconcile(
                    findings: candidates,
                    detections: detections,
                    snapshot: snapshot,
                    artifact: self
                )
                for match in reconciliation.matches { try legacyRequire(match: match, snapshotID: snapshot.id) }
                for group in reconciliation.unresolvedGroups {
                    try legacyRequire(group: group, snapshotID: snapshot.id)
                }
                for detection in reconciliation.newDetections {
                    try legacyRequireOpening(of: detection, snapshotID: snapshot.id)
                }
            }
        }
    }

    private func legacyRequireOpening(of detection: ObservedDetection, snapshotID: SnapshotID) throws {
        let openings = findings.filter { finding in
            guard let first = finding.events.first, first.snapshotID == snapshotID,
                case .opened(let evidence) = first.transition
            else { return false }
            return evidence.detectionID == detection.id
        }
        guard openings.count == 1 else {
            throw LifecycleContractError.invalidArtifact(
                "Detection \(detection.id) must open exactly one new Finding."
            )
        }
    }

    private func legacyRequire(match: LegacyContinuityMatch, snapshotID: SnapshotID) throws {
        guard let finding = findings.first(where: { $0.id == match.finding.id }),
            let event = finding.events.first(where: { $0.snapshotID == snapshotID })
        else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(match.finding.id) is missing its unique continuation event."
            )
        }
        let detectionID: DetectionID?
        switch event.transition {
        case .observed(let evidence), .reopened(let evidence):
            detectionID = evidence.currentDetection.detectionID
        case .opened, .resolved, .unverified, .continuityAmbiguous:
            detectionID = nil
        }
        guard detectionID == match.currentDetection.id else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(match.finding.id) did not record its uniquely matched Detection."
            )
        }
    }

    private func legacyRequire(group: LegacyContinuityUnresolvedGroup, snapshotID: SnapshotID) throws {
        let candidateIDs = group.findings.map(\.id).sorted { $0.rawValue < $1.rawValue }
        let detectionIDs = group.detections.map(\.id).sorted { $0.rawValue < $1.rawValue }
        for detectionID in detectionIDs {
            guard
                let unresolved = unresolvedDetections.first(where: {
                    $0.snapshotID == snapshotID && $0.detectionID == detectionID
                }),
                unresolved.candidateFindingIDs == candidateIDs,
                unresolved.reasons == group.reasons
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Unresolved Detection \(detectionID) does not preserve its complete candidate set."
                )
            }
        }
        for candidateID in candidateIDs {
            guard let priorFinding = group.findings.first(where: { $0.id == candidateID }),
                let finding = findings.first(where: { $0.id == candidateID })
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(candidateID) is missing from its unresolved continuity group."
                )
            }
            if priorFinding.lifecycleState == .resolved {
                guard !finding.events.contains(where: { $0.snapshotID == snapshotID }) else {
                    throw LifecycleContractError.invalidArtifact(
                        "Resolved Finding \(candidateID) cannot replace verified evidence with uncertainty."
                    )
                }
                continue
            }
            guard let event = finding.events.first(where: { $0.snapshotID == snapshotID }) else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(candidateID) is missing its unresolved continuity event."
                )
            }
            switch event.transition {
            case .continuityAmbiguous(let evidence) where group.isAmbiguous:
                guard evidence.currentDetectionIDs == detectionIDs,
                    evidence.candidateFindingIDs == candidateIDs,
                    evidence.reasons == group.reasons
                else {
                    throw LifecycleContractError.invalidArtifact(
                        "Finding \(candidateID) has incomplete continuity ambiguity evidence."
                    )
                }
            case .unverified(let reasons) where !group.isAmbiguous:
                guard reasons == group.reasons else {
                    throw LifecycleContractError.invalidArtifact(
                        "Finding \(candidateID) has incomplete comparability blockers."
                    )
                }
            default:
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(candidateID) selected an unsupported continuity outcome."
                )
            }
        }
    }
}
