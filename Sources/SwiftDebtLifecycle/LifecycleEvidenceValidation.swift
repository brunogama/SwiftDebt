extension LifecycleArtifact {
    func validate(
        finding: Finding,
        snapshots: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>,
        findings: [FindingID: Finding]
    ) throws {
        guard Set(finding.events.map(\.snapshotID)).count == finding.events.count else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) has more than one event in a snapshot projection."
            )
        }
        let eventByID = Dictionary(uniqueKeysWithValues: finding.events.map { ($0.id, $0) })
        for event in finding.events {
            guard let snapshot = snapshots[event.snapshotID], processed.contains(event.snapshotID) else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) references a missing or unprocessed snapshot."
                )
            }
            let parentProjection: FindingProjection?
            if let parentID = parentSnapshotID(of: event.snapshotID) {
                parentProjection = try findingProjection(finding, at: parentID)
            } else {
                parentProjection = nil
            }
            let expectedBasis = parentProjection?.finding.events.last?.id
            guard event.basisEventIDs == (expectedBasis.map { [$0] } ?? []) else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) event basis does not match its selected parent projection."
                )
            }
            if let basisID = expectedBasis {
                guard let basisEvent = eventByID[basisID],
                    isAncestor(basisEvent.snapshotID, of: event.snapshotID)
                else {
                    throw LifecycleContractError.invalidArtifact(
                        "Finding \(finding.id) event basis crosses unrelated snapshot branches."
                    )
                }
            }
            guard let projection = try findingProjection(finding, at: event.snapshotID) else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) has no projection at one of its events."
                )
            }
            try validate(
                event.transition,
                semanticComparisons: event.semanticComparisons,
                finding: projection.finding,
                snapshot: snapshot,
                findings: findings
            )
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
                !unresolved.reasons.isEmpty
            else {
                throw LifecycleContractError.invalidArtifact("An Unresolved Detection has a broken reference.")
            }
            let candidates = try parentFindingProjections(of: snapshot.id)
            let eligibleIDs = Set(
                candidates.compactMap { projection -> FindingID? in
                    projection.finding.rule.identity == detection.rule.identity
                        ? projection.finding.id : nil
                })
            guard
                unresolved.candidateFindingIDs.allSatisfy({ candidateID in
                    findings[candidateID] != nil && eligibleIDs.contains(candidateID)
                })
            else {
                throw LifecycleContractError.invalidArtifact(
                    "An Unresolved Detection references a Finding outside its parent projection."
                )
            }
        }
    }

    private func validate(
        _ transition: LifecycleTransition,
        semanticComparisons: [SemanticComparisonBasis],
        finding: Finding,
        snapshot: ObservationSnapshot,
        findings: [FindingID: Finding]
    ) throws {
        switch transition {
        case .opened(let evidence):
            guard semanticComparisons.isEmpty,
                let detection = snapshot.detection(id: evidence.detectionID),
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
                semanticComparisons: semanticComparisons,
                finding: finding,
                snapshot: snapshot
            )
        case .resolved(let evidence):
            let assessment = try ResolutionCoverageEvaluator().assess(
                finding: finding,
                snapshot: snapshot,
                artifact: self
            )
            guard
                case .verified(
                    let expectedAtomicIDs,
                    let expectedReasons,
                    let expectedComparisons
                ) = assessment,
                evidence.priorSnapshotID == finding.firstObservationSnapshotID,
                evidence.coveredAtomicObservationIDs == expectedAtomicIDs,
                evidence.reasons == expectedReasons,
                semanticComparisons == expectedComparisons
            else {
                throw LifecycleContractError.invalidArtifact("A resolved event has incomplete evidence references.")
            }
        case .unverified(let reasons):
            guard !reasons.isEmpty else {
                throw LifecycleContractError.invalidArtifact("An unverified event requires blockers.")
            }
            if !snapshot.detections.contains(where: { $0.rule.identity == finding.rule.identity }) {
                guard let eventIndex = finding.events.firstIndex(where: { $0.snapshotID == snapshot.id }) else {
                    throw LifecycleContractError.invalidArtifact(
                        "An unverified event is missing from its Finding history."
                    )
                }
                let findingAtAssessment = try Finding(
                    id: finding.id,
                    lineageID: finding.lineageID,
                    rule: finding.rule,
                    events: Array(finding.events[...eventIndex])
                )
                let assessment = try ResolutionCoverageEvaluator().assess(
                    finding: findingAtAssessment,
                    snapshot: snapshot,
                    artifact: self
                )
                guard case .unverified(let expectedReasons, let expectedComparisons) = assessment,
                    reasons == expectedReasons,
                    semanticComparisons == expectedComparisons
                else {
                    throw LifecycleContractError.invalidArtifact(
                        "An unverified absence event does not match its persisted comparison evidence."
                    )
                }
            }
        case .continuityAmbiguous(let evidence):
            let eligibleIDs = Set(
                try parentFindingProjections(of: snapshot.id).compactMap { projection in
                    projection.finding.rule.identity == finding.rule.identity ? projection.finding.id : nil
                })
            guard !evidence.currentDetectionIDs.isEmpty,
                !evidence.candidateFindingIDs.isEmpty,
                !evidence.reasons.isEmpty,
                Set(evidence.currentDetectionIDs).count == evidence.currentDetectionIDs.count,
                Set(evidence.candidateFindingIDs).count == evidence.candidateFindingIDs.count,
                evidence.currentDetectionIDs.allSatisfy({ detectionID in
                    snapshot.detection(id: detectionID)?.rule.identity == finding.rule.identity
                }),
                evidence.candidateFindingIDs.allSatisfy({ candidateID in
                    findings[candidateID]?.rule.identity == finding.rule.identity
                        && eligibleIDs.contains(candidateID)
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
