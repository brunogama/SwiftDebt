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
        guard Set(legacyProcessedSnapshotIDs).count == legacyProcessedSnapshotIDs.count,
            Set(legacyProcessedSnapshotIDs).isSubset(of: Set(processedSnapshotIDs))
        else {
            throw LifecycleContractError.invalidArtifact("Legacy snapshot boundary is invalid.")
        }

        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        let processed = Set(processedSnapshotIDs)
        let legacy = Set(legacyProcessedSnapshotIDs)
        for finding in findings {
            for event in finding.events {
                guard (event.evidenceContract == .legacySchemaTwo) == legacy.contains(event.snapshotID),
                    event.evidenceContract != .legacySchemaTwo || event.semanticComparisons.isEmpty
                else {
                    throw LifecycleContractError.invalidArtifact(
                        "Event evidence contract crosses its migration boundary.")
                }
            }
        }
        try validateSnapshotGraph(snapshotByID: snapshotByID, processed: processed)
        try validateFindings(snapshotByID: snapshotByID, processed: processed)
        try validateIntroductionConclusions()
    }

    private func validateSnapshotGraph(
        snapshotByID: [SnapshotID: ObservationSnapshot],
        processed: Set<SnapshotID>
    ) throws {
        guard processed.allSatisfy({ snapshotByID[$0] != nil }) else {
            throw LifecycleContractError.invalidArtifact("A processed snapshot reference is broken.")
        }
        guard Set(snapshotParentEdges.map(\.childSnapshotID)).count == snapshotParentEdges.count else {
            throw LifecycleContractError.invalidArtifact(
                "The snapshot graph supports at most one parent per snapshot; merge nodes are unsupported."
            )
        }
        for edge in snapshotParentEdges {
            guard edge.childSnapshotID != edge.parentSnapshotID,
                let child = snapshotByID[edge.childSnapshotID]
            else {
                throw LifecycleContractError.invalidArtifact("A snapshot parent edge has a broken child reference.")
            }
            if let parent = snapshotByID[edge.parentSnapshotID] {
                try validate(edge: edge, child: child, parent: parent)
            } else if processed.contains(edge.childSnapshotID) {
                throw LifecycleContractError.invalidArtifact(
                    "Processed snapshot \(edge.childSnapshotID) has a missing graph parent."
                )
            }
            guard !processed.contains(edge.childSnapshotID) || processed.contains(edge.parentSnapshotID) else {
                throw LifecycleContractError.invalidArtifact(
                    "Processed snapshot \(edge.childSnapshotID) follows an unprocessed graph parent."
                )
            }
        }
        for snapshot in snapshots {
            let declaredParent = snapshot.provenance.lineage.predecessorSnapshotID
            let edge = parentEdge(of: snapshot.id)
            if let declaredParent {
                guard edge?.parentSnapshotID == declaredParent else {
                    throw LifecycleContractError.invalidArtifact(
                        "Snapshot \(snapshot.id) lost its explicit predecessor edge."
                    )
                }
            }
            if processed.contains(snapshot.id), snapshot.provenance.lineage.sequence > 1,
                declaredParent != nil, edge == nil
            {
                throw LifecycleContractError.invalidArtifact(
                    "Processed snapshot \(snapshot.id) has no graph parent."
                )
            }
        }
        for snapshotID in snapshotByID.keys {
            var cursor: SnapshotID? = snapshotID
            var visited: Set<SnapshotID> = []
            while let current = cursor {
                guard visited.insert(current).inserted else {
                    throw LifecycleContractError.invalidArtifact("Snapshot graph contains a cycle.")
                }
                cursor = parentSnapshotID(of: current)
            }
        }
    }

    private func validate(
        edge: SnapshotParentEdge,
        child: ObservationSnapshot,
        parent: ObservationSnapshot
    ) throws {
        switch edge.basis {
        case .explicitPredecessor, .migratedSchemaOne:
            let childPosition = child.provenance.lineage
            let parentPosition = parent.provenance.lineage
            guard childPosition.predecessorSnapshotID == parent.id,
                childPosition.lineageID == parentPosition.lineageID,
                childPosition.sequence == parentPosition.sequence + 1
            else {
                throw LifecycleContractError.invalidArtifact(
                    "An explicit snapshot predecessor is inconsistent with legacy lineage provenance."
                )
            }
        case .gitDirectParent(let parentRevision):
            guard case .git(_, let childState, _) = child.provenance.sourceIdentity,
                case .git(let observedParentRevision, let parentState, _) = parent.provenance.sourceIdentity,
                childState == .clean,
                parentState == .clean,
                observedParentRevision == parentRevision,
                child.provenance.lineage.predecessorSnapshotID == parent.id,
                child.provenance.lineage.lineageID == parent.provenance.lineage.lineageID,
                child.provenance.lineage.sequence == parent.provenance.lineage.sequence + 1
            else {
                throw LifecycleContractError.invalidArtifact(
                    "A Git snapshot edge does not match one clean persisted parent revision."
                )
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
