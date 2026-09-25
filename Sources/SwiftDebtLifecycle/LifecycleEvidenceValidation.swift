extension LifecycleArtifact {
    func validate(
        finding: Finding,
        snapshots: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>,
        findings: [FindingID: Finding]
    ) throws {
        let eventSequences = try finding.events.map { event -> UInt in
            guard let snapshot = snapshots[event.snapshotID] else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) references a missing snapshot."
                )
            }
            return snapshot.provenance.lineage.sequence
        }
        guard zip(eventSequences, eventSequences.dropFirst()).allSatisfy({ pair in pair.0 < pair.1 }) else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) events must follow strict lineage order."
            )
        }
        for event in finding.events {
            guard let snapshot = snapshots[event.snapshotID],
                processed.contains(event.snapshotID),
                snapshot.provenance.lineage.lineageID == finding.lineageID
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) references a missing or unrelated snapshot."
                )
            }
            try validate(event.transition, finding: finding, snapshot: snapshot, findings: findings)
        }
    }

    func validateUnresolvedDetections(
        snapshots: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>,
        findings: [FindingID: Finding]
    ) throws {
        let unresolvedKeys = unresolvedDetections.map {
            "\($0.snapshotID.rawValue):\($0.detectionID.rawValue)"
        }
        guard Set(unresolvedKeys).count == unresolvedKeys.count else {
            throw LifecycleContractError.invalidArtifact("Unresolved Detection records must be unique.")
        }
        for unresolved in unresolvedDetections {
            guard let snapshot = snapshots[unresolved.snapshotID],
                processed.contains(unresolved.snapshotID),
                let detection = snapshot.detection(id: unresolved.detectionID),
                !unresolved.candidateFindingIDs.isEmpty,
                Set(unresolved.candidateFindingIDs).count == unresolved.candidateFindingIDs.count,
                unresolved.candidateFindingIDs
                    == unresolved.candidateFindingIDs.sorted(by: { $0.rawValue < $1.rawValue }),
                unresolved.candidateFindingIDs.allSatisfy({ candidateID in
                    guard let candidate = findings[candidateID] else { return false }
                    return candidate.lineageID == snapshot.provenance.lineage.lineageID
                        && candidate.rule.identity == detection.rule.identity
                }),
                !unresolved.reasons.isEmpty
            else {
                throw LifecycleContractError.invalidArtifact("An Unresolved Detection has a broken reference.")
            }
        }
    }

    private func validate(
        _ transition: LifecycleTransition,
        finding: Finding,
        snapshot: ObservationSnapshot,
        findings: [FindingID: Finding]
    ) throws {
        switch transition {
        case .opened(let evidence):
            guard let detection = snapshot.detection(id: evidence.detectionID),
                let atomic = snapshot.atomicObservation(id: evidence.atomicObservationID),
                detection.rule == finding.rule,
                atomic.rule == finding.rule,
                atomic.sourcePath == detection.location.sourcePath,
                atomic.outcome.references(evidence.detectionID)
            else {
                throw LifecycleContractError.invalidArtifact("An opened event has a broken Detection reference.")
            }
        case .observed(let evidence), .reopened(let evidence):
            try validateMatchedContinuity(
                evidence,
                finding: finding,
                snapshot: snapshot,
                findings: findings
            )
        case .resolved(let evidence):
            guard let eventIndex = finding.events.firstIndex(where: { $0.snapshotID == snapshot.id }) else {
                throw LifecycleContractError.invalidArtifact(
                    "A resolved event is missing from its Finding history."
                )
            }
            let findingAtResolution = try Finding(
                id: finding.id,
                lineageID: finding.lineageID,
                rule: finding.rule,
                events: Array(finding.events[...eventIndex])
            )
            let assessment = try ResolutionCoverageEvaluator().assess(
                finding: findingAtResolution,
                snapshot: snapshot,
                artifact: self
            )
            guard case .verified(let expectedAtomicIDs, let expectedReasons) = assessment,
                evidence.priorSnapshotID == findingAtResolution.firstObservationSnapshotID,
                evidence.coveredAtomicObservationIDs == expectedAtomicIDs,
                evidence.reasons == expectedReasons
            else {
                throw LifecycleContractError.invalidArtifact("A resolved event has incomplete evidence references.")
            }
        case .unverified(let reasons):
            guard !reasons.isEmpty else {
                throw LifecycleContractError.invalidArtifact("An unverified event requires blockers.")
            }
        case .continuityAmbiguous(let evidence):
            guard !evidence.currentDetectionIDs.isEmpty,
                !evidence.candidateFindingIDs.isEmpty,
                !evidence.reasons.isEmpty,
                Set(evidence.currentDetectionIDs).count == evidence.currentDetectionIDs.count,
                Set(evidence.candidateFindingIDs).count == evidence.candidateFindingIDs.count,
                evidence.currentDetectionIDs.allSatisfy({ detectionID in
                    snapshot.detection(id: detectionID)?.rule.identity == finding.rule.identity
                }),
                evidence.candidateFindingIDs.allSatisfy({ candidateID in
                    guard let candidate = findings[candidateID] else { return false }
                    return candidate.lineageID == finding.lineageID
                        && candidate.rule.identity == finding.rule.identity
                }),
                evidence.candidateFindingIDs.contains(finding.id)
            else {
                throw LifecycleContractError.invalidArtifact("A continuity ambiguity has incomplete evidence.")
            }
        }
    }

}

extension AtomicObservationOutcome {
    func references(_ detectionID: DetectionID) -> Bool {
        guard case .committed(let detectionIDs) = self else { return false }
        return detectionIDs.contains(detectionID)
    }
}
