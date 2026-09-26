import SwiftDebtCore

public enum SnapshotIngestionStatus: String, Codable, Equatable, Sendable {
    case accepted
    case alreadyPresent = "already-present"
}

public struct LifecycleReduction: Equatable, Sendable {
    public let artifact: LifecycleArtifact
    public let status: SnapshotIngestionStatus
    public let processedSnapshotIDs: [SnapshotID]

    public init(
        artifact: LifecycleArtifact,
        status: SnapshotIngestionStatus,
        processedSnapshotIDs: [SnapshotID]
    ) {
        self.artifact = artifact
        self.status = status
        self.processedSnapshotIDs = processedSnapshotIDs
    }
}

public struct LifecycleReducer: Sendable {
    public init() {}

    public func ingest(
        _ snapshot: ObservationSnapshot,
        into artifact: LifecycleArtifact
    ) throws -> LifecycleReduction {
        try ingest(.explicit(snapshot), into: artifact)
    }

    package func ingest(
        _ input: LifecycleSnapshotIngestion,
        into artifact: LifecycleArtifact
    ) throws -> LifecycleReduction {
        try artifact.validate()
        let snapshot = input.snapshot
        if let existing = artifact.snapshot(id: snapshot.id) {
            guard existing == snapshot,
                artifact.parentSnapshotID(of: snapshot.id) == input.parentEdge?.parentSnapshotID
            else {
                throw LifecycleContractError.conflictingSnapshot(snapshot.id.rawValue)
            }
            return LifecycleReduction(
                artifact: artifact,
                status: .alreadyPresent,
                processedSnapshotIDs: []
            )
        }
        if let edge = input.parentEdge {
            guard edge.childSnapshotID == snapshot.id else {
                throw LifecycleContractError.invalidSnapshot(
                    "Snapshot graph edge child does not match the ingested snapshot."
                )
            }
        }

        var updated = artifact
        updated.snapshots.append(snapshot)
        if let edge = input.parentEdge { updated.snapshotParentEdges.append(edge) }

        var newlyProcessed: [SnapshotID] = []
        while let next = nextProcessableSnapshot(in: updated) {
            try process(next, artifact: &updated)
            updated.processedSnapshotIDs.append(next.id)
            newlyProcessed.append(next.id)
        }

        updated = try LifecycleArtifact(
            schemaVersion: updated.schemaVersion,
            reportKind: updated.reportKind,
            generatorVersion: updated.generatorVersion,
            snapshots: updated.snapshots,
            snapshotParentEdges: updated.snapshotParentEdges,
            findings: updated.findings,
            unresolvedDetections: updated.unresolvedDetections,
            processedSnapshotIDs: updated.processedSnapshotIDs,
            introductionConclusions: updated.introductionConclusions
        )
        return LifecycleReduction(
            artifact: updated,
            status: .accepted,
            processedSnapshotIDs: newlyProcessed
        )
    }

    private func nextProcessableSnapshot(in artifact: LifecycleArtifact) -> ObservationSnapshot? {
        let processed = Set(artifact.processedSnapshotIDs)
        return artifact.snapshots
            .filter { snapshot in
                guard !processed.contains(snapshot.id) else { return false }
                guard let parentID = artifact.parentSnapshotID(of: snapshot.id) else { return true }
                return processed.contains(parentID)
            }
            .sorted { $0.id.rawValue < $1.id.rawValue }
            .first
    }
}
