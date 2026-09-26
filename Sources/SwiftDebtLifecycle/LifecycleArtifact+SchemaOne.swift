private struct SchemaOneFinding: Decodable {
    let id: FindingID
    let lineageID: LineageID
    let rule: SnapshotRule
    let events: [SchemaOneEvent]
}

private struct SchemaOneEvent: Decodable {
    let id: LifecycleEventID
    let snapshotID: SnapshotID
    let transition: LifecycleTransition
}

extension LifecycleArtifact {
    init(migratingSchemaOne values: KeyedDecodingContainer<CodingKeys>) throws {
        let reportKind = try values.decode(String.self, forKey: .reportKind)
        guard reportKind == LifecycleArtifactSchema.reportKind else {
            throw LifecycleContractError.invalidArtifact("Unexpected report kind \(reportKind).")
        }
        let snapshots = try values.decode([ObservationSnapshot].self, forKey: .snapshots)
        let processed = try values.decode([SnapshotID].self, forKey: .processedSnapshotIDs)
        let heads = try values.decode([LineageHead].self, forKey: .lineageHeads)
        try Self.validateSchemaOneLineages(snapshots: snapshots, processed: processed, heads: heads)

        let legacyFindings = try values.decode([SchemaOneFinding].self, forKey: .findings)
        let findings = try legacyFindings.map { legacy in
            var priorEventID: LifecycleEventID?
            let migrated = legacy.events.map { event -> LifecycleEvent in
                let value = LifecycleEvent(
                    id: event.id,
                    snapshotID: event.snapshotID,
                    basisEventIDs: priorEventID.map { [$0] } ?? [],
                    transition: event.transition
                )
                priorEventID = event.id
                return value
            }
            return try Finding(
                id: legacy.id,
                lineageID: legacy.lineageID,
                rule: legacy.rule,
                events: migrated
            )
        }
        let edges = snapshots.compactMap { snapshot -> SnapshotParentEdge? in
            guard let parentID = snapshot.provenance.lineage.predecessorSnapshotID else { return nil }
            return SnapshotParentEdge(
                childSnapshotID: snapshot.id,
                parentSnapshotID: parentID,
                basis: .migratedSchemaOne
            )
        }
        try self.init(
            schemaVersion: LifecycleArtifactSchema.currentVersion,
            reportKind: reportKind,
            generatorVersion: values.decode(String.self, forKey: .generatorVersion),
            snapshots: snapshots,
            snapshotParentEdges: edges,
            findings: findings,
            unresolvedDetections: values.decode([UnresolvedDetection].self, forKey: .unresolvedDetections),
            processedSnapshotIDs: processed,
            introductionConclusions: values.decodeIfPresent(
                [IntroductionConclusion].self,
                forKey: .introductionConclusions
            ) ?? []
        )
    }

    private static func validateSchemaOneLineages(
        snapshots: [ObservationSnapshot],
        processed: [SnapshotID],
        heads: [LineageHead]
    ) throws {
        guard Set(snapshots.map(\.id)).count == snapshots.count,
            Set(processed).count == processed.count
        else {
            throw LifecycleContractError.invalidArtifact("Schema 1 snapshot references are invalid.")
        }
        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        guard
            processed.allSatisfy({ snapshotByID[$0] != nil })
        else {
            throw LifecycleContractError.invalidArtifact("Schema 1 snapshot references are invalid.")
        }
        let positions = snapshots.map {
            "\($0.provenance.lineage.lineageID.rawValue):\($0.provenance.lineage.sequence)"
        }
        guard Set(positions).count == positions.count,
            Set(heads.map(\.lineageID)).count == heads.count
        else {
            throw LifecycleContractError.invalidArtifact("Schema 1 lineage positions are invalid.")
        }
        let processedSet = Set(processed)
        for snapshot in snapshots {
            let position = snapshot.provenance.lineage
            guard position.sequence > 1 else { continue }
            if let predecessorID = position.predecessorSnapshotID,
                let predecessor = snapshotByID[predecessorID]
            {
                guard predecessor.provenance.lineage.lineageID == position.lineageID,
                    predecessor.provenance.lineage.sequence + 1 == position.sequence
                else {
                    throw LifecycleContractError.invalidArtifact("Schema 1 predecessor is inconsistent.")
                }
                guard !processedSet.contains(snapshot.id) || processedSet.contains(predecessorID) else {
                    throw LifecycleContractError.invalidArtifact("Schema 1 processed order is invalid.")
                }
            } else if processedSet.contains(snapshot.id) {
                throw LifecycleContractError.invalidArtifact("Schema 1 processed predecessor is invalid.")
            }
        }
        let processedLineages = Set(processed.compactMap { snapshotByID[$0]?.provenance.lineage.lineageID })
        guard processedLineages == Set(heads.map(\.lineageID)) else {
            throw LifecycleContractError.invalidArtifact("Schema 1 lineage heads are incomplete.")
        }
        for head in heads {
            let lineageSnapshots = processed.compactMap { snapshotByID[$0] }.filter {
                $0.provenance.lineage.lineageID == head.lineageID
            }
            guard let snapshot = snapshotByID[head.snapshotID],
                processedSet.contains(head.snapshotID),
                snapshot.provenance.lineage.lineageID == head.lineageID,
                snapshot.provenance.lineage.sequence == head.sequence,
                lineageSnapshots.map({ $0.provenance.lineage.sequence }).max() == head.sequence
            else {
                throw LifecycleContractError.invalidArtifact("Schema 1 lineage head is invalid.")
            }
        }
    }
}
