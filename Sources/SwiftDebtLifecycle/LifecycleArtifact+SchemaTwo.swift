private struct SchemaTwoEvent: Decodable {
    let id: LifecycleEventID
    let snapshotID: SnapshotID
    let basisEventIDs: [LifecycleEventID]
    let transition: LifecycleTransition

    private enum CodingKeys: String, CodingKey {
        case id, snapshotID, basisEventIDs, transition, semanticComparisons, evidenceContract
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard !values.contains(.semanticComparisons), !values.contains(.evidenceContract) else {
            throw LifecycleContractError.invalidArtifact("Schema 2 cannot contain schema 3 evidence.")
        }
        id = try values.decode(LifecycleEventID.self, forKey: .id)
        snapshotID = try values.decode(SnapshotID.self, forKey: .snapshotID)
        basisEventIDs = try values.decode([LifecycleEventID].self, forKey: .basisEventIDs)
        transition = try values.decode(LifecycleTransition.self, forKey: .transition)
    }

    var migrated: LifecycleEvent {
        LifecycleEvent(
            id: id,
            snapshotID: snapshotID,
            basisEventIDs: basisEventIDs,
            transition: transition,
            evidenceContract: .legacySchemaTwo
        )
    }
}

private struct SchemaTwoFinding: Decodable {
    let id: FindingID
    let lineageID: LineageID
    let rule: SnapshotRule
    let events: [SchemaTwoEvent]

    func migrated() throws -> Finding {
        try Finding(id: id, lineageID: lineageID, rule: rule, events: events.map(\.migrated))
    }
}

struct LegacyIntroductionConclusion: Decodable {
    let findingID: FindingID
    let attempt: UInt
    let kind: IntroductionConclusionKind
    let exactRevision: GitRevisionID?
    let earliestPositiveRevision: GitRevisionID?
    let reasons: [LifecycleReason]
    let evidence: IntroductionHistoryEvidence

    private enum CodingKeys: String, CodingKey {
        case findingID, attempt, kind, exactRevision, earliestPositiveRevision, reasons, evidence
        case semanticComparisons, evidenceContract
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard !values.contains(.semanticComparisons), !values.contains(.evidenceContract) else {
            throw LifecycleContractError.invalidArtifact("Legacy introduction cannot contain schema 3 evidence.")
        }
        findingID = try values.decode(FindingID.self, forKey: .findingID)
        attempt = try values.decode(UInt.self, forKey: .attempt)
        kind = try values.decode(IntroductionConclusionKind.self, forKey: .kind)
        exactRevision = try values.decodeIfPresent(GitRevisionID.self, forKey: .exactRevision)
        earliestPositiveRevision = try values.decodeIfPresent(GitRevisionID.self, forKey: .earliestPositiveRevision)
        reasons = try values.decode([LifecycleReason].self, forKey: .reasons)
        evidence = try values.decode(IntroductionHistoryEvidence.self, forKey: .evidence)
    }

    var migrated: IntroductionConclusion {
        IntroductionConclusion(
            findingID: findingID,
            attempt: attempt,
            kind: kind,
            exactRevision: exactRevision,
            earliestPositiveRevision: earliestPositiveRevision,
            reasons: reasons,
            evidence: evidence,
            semanticComparisons: [],
            evidenceContract: .legacySchemaTwo
        )
    }
}

extension LifecycleArtifact {
    init(migratingSchemaTwo values: KeyedDecodingContainer<CodingKeys>) throws {
        guard !values.contains(.legacyProcessedSnapshotIDs), !values.contains(.lineageHeads) else {
            throw LifecycleContractError.invalidArtifact("Schema 2 contains fields from another artifact version.")
        }
        let findings = try values.decode([SchemaTwoFinding].self, forKey: .findings)
            .map { try $0.migrated() }
        let processed = try values.decode([SnapshotID].self, forKey: .processedSnapshotIDs)
        try self.init(
            schemaVersion: LifecycleArtifactSchema.currentVersion,
            reportKind: values.decode(String.self, forKey: .reportKind),
            generatorVersion: values.decode(String.self, forKey: .generatorVersion),
            snapshots: values.decode([ObservationSnapshot].self, forKey: .snapshots),
            snapshotParentEdges: values.decode([SnapshotParentEdge].self, forKey: .snapshotParentEdges),
            findings: findings,
            unresolvedDetections: values.decode([UnresolvedDetection].self, forKey: .unresolvedDetections),
            processedSnapshotIDs: processed,
            introductionConclusions: values.decodeIfPresent(
                [LegacyIntroductionConclusion].self,
                forKey: .introductionConclusions
            )?.map(\.migrated) ?? [],
            legacyProcessedSnapshotIDs: processed
        )
    }
}
