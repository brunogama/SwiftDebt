extension LifecycleArtifact {
    public func validate() throws {
        guard schemaVersion == LifecycleArtifactSchema.currentVersion,
            reportKind == LifecycleArtifactSchema.reportKind
        else {
            throw LifecycleContractError.invalidArtifact("Unsupported lifecycle artifact identity.")
        }
        guard Set(snapshots.map(\.id)).count == snapshots.count else {
            throw LifecycleContractError.invalidArtifact("Snapshot IDs must be unique.")
        }
        guard Set(findings.map(\.id)).count == findings.count else {
            throw LifecycleContractError.invalidArtifact("Finding IDs must be unique.")
        }
        guard Set(processedSnapshotIDs).count == processedSnapshotIDs.count else {
            throw LifecycleContractError.invalidArtifact("Processed snapshot IDs must be unique.")
        }

        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let processed = Set(processedSnapshotIDs)
        try validateLineages(snapshotByID: snapshotByID, processed: processed)
        try validateFindings(snapshotByID: snapshotByID, processed: processed)
    }

    private func validateLineages(
        snapshotByID: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        let lineagePositions = snapshots.map {
            "\($0.provenance.lineage.lineageID.rawValue):\($0.provenance.lineage.sequence)"
        }
        guard Set(lineagePositions).count == lineagePositions.count else {
            throw LifecycleContractError.invalidArtifact("A lineage cannot contain duplicate sequence positions.")
        }
        guard processedSnapshotIDs.allSatisfy({ snapshotByID[$0] != nil }) else {
            throw LifecycleContractError.invalidArtifact("A processed snapshot reference is broken.")
        }
        guard Set(lineageHeads.map(\.lineageID)).count == lineageHeads.count else {
            throw LifecycleContractError.invalidArtifact("A lineage can have only one processed head.")
        }
        for snapshot in snapshots {
            let position = snapshot.provenance.lineage
            guard position.sequence > 1 else { continue }
            if let predecessorID = position.predecessorSnapshotID,
                let predecessor = snapshotByID[predecessorID]
            {
                guard predecessor.provenance.lineage.lineageID == position.lineageID,
                    predecessor.provenance.lineage.sequence + 1 == position.sequence
                else {
                    throw LifecycleContractError.invalidArtifact(
                        "Snapshot \(snapshot.id) has an inconsistent predecessor."
                    )
                }
                guard !processed.contains(snapshot.id) || processed.contains(predecessorID) else {
                    throw LifecycleContractError.invalidArtifact(
                        "Processed snapshot \(snapshot.id) follows an unprocessed predecessor."
                    )
                }
            } else if processed.contains(snapshot.id) {
                throw LifecycleContractError.invalidArtifact(
                    "Processed snapshot \(snapshot.id) has a missing predecessor."
                )
            }
        }
        try validateLineageHeads(snapshotByID: snapshotByID, processed: processed)
    }

    private func validateLineageHeads(
        snapshotByID: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        for head in lineageHeads {
            guard let snapshot = snapshotByID[head.snapshotID],
                processed.contains(head.snapshotID),
                snapshot.provenance.lineage.lineageID == head.lineageID,
                snapshot.provenance.lineage.sequence == head.sequence
            else {
                throw LifecycleContractError.invalidArtifact("Lineage head \(head.lineageID) is inconsistent.")
            }
        }
        let processedLineages = Set(processed.compactMap { snapshotByID[$0]?.provenance.lineage.lineageID })
        guard processedLineages == Set(lineageHeads.map(\.lineageID)) else {
            throw LifecycleContractError.invalidArtifact("Every processed lineage requires exactly one head.")
        }
        for lineageID in processedLineages {
            let lineageSnapshots = processed.compactMap { snapshotByID[$0] }.filter {
                $0.provenance.lineage.lineageID == lineageID
            }
            guard let maximum = lineageSnapshots.map({ $0.provenance.lineage.sequence }).max(),
                let head = lineageHeads.first(where: { $0.lineageID == lineageID }),
                maximum == head.sequence
            else {
                throw LifecycleContractError.invalidArtifact("Lineage \(lineageID) has an invalid processed head.")
            }
        }
    }

    private func validateFindings(
        snapshotByID: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        let findingByID = Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) })
        let eventIDs = findings.flatMap { $0.events.map(\.id) }
        guard Set(eventIDs).count == eventIDs.count else {
            throw LifecycleContractError.invalidArtifact("Lifecycle event IDs must be globally unique.")
        }
        for finding in findings {
            try validate(finding: finding, snapshots: snapshotByID, processed: processed, findings: findingByID)
        }
        try validateUnresolvedDetections(snapshots: snapshotByID, processed: processed, findings: findingByID)
        try validateDerivedState(snapshots: snapshotByID, processed: processed)
    }
}
