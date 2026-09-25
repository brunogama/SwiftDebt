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
        try artifact.validate()
        if let existing = artifact.snapshot(id: snapshot.id) {
            guard existing == snapshot else {
                throw LifecycleContractError.conflictingSnapshot(snapshot.id.rawValue)
            }
            return LifecycleReduction(
                artifact: artifact,
                status: .alreadyPresent,
                processedSnapshotIDs: []
            )
        }

        var updated = artifact
        updated.snapshots.append(snapshot)
        let positions = updated.snapshots.map {
            LineageSequence(lineageID: $0.provenance.lineage.lineageID, sequence: $0.provenance.lineage.sequence)
        }
        guard Set(positions).count == positions.count else {
            throw LifecycleContractError.invalidArtifact(
                "A lineage cannot contain two snapshots at the same sequence."
            )
        }

        var newlyProcessed: [SnapshotID] = []
        while let next = nextProcessableSnapshot(in: updated) {
            try process(next, artifact: &updated)
            updated.processedSnapshotIDs.append(next.id)
            updated.lineageHeads.removeAll { $0.lineageID == next.provenance.lineage.lineageID }
            updated.lineageHeads.append(
                LineageHead(
                    lineageID: next.provenance.lineage.lineageID,
                    snapshotID: next.id,
                    sequence: next.provenance.lineage.sequence
                )
            )
            newlyProcessed.append(next.id)
        }

        updated = try LifecycleArtifact(
            schemaVersion: updated.schemaVersion,
            reportKind: updated.reportKind,
            generatorVersion: updated.generatorVersion,
            snapshots: updated.snapshots,
            findings: updated.findings,
            unresolvedDetections: updated.unresolvedDetections,
            processedSnapshotIDs: updated.processedSnapshotIDs,
            lineageHeads: updated.lineageHeads
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
            .filter { !processed.contains($0.id) && isProcessable($0, heads: artifact.lineageHeads) }
            .sorted(by: snapshotOrder)
            .first
    }

    private func isProcessable(_ snapshot: ObservationSnapshot, heads: [LineageHead]) -> Bool {
        let position = snapshot.provenance.lineage
        guard let head = heads.first(where: { $0.lineageID == position.lineageID }) else {
            return position.sequence == 1 && position.predecessorSnapshotID == nil
        }
        return position.sequence == head.sequence + 1 && position.predecessorSnapshotID == head.snapshotID
    }

    private func snapshotOrder(_ lhs: ObservationSnapshot, _ rhs: ObservationSnapshot) -> Bool {
        let left = lhs.provenance.lineage
        let right = rhs.provenance.lineage
        if left.lineageID != right.lineageID { return left.lineageID.rawValue < right.lineageID.rawValue }
        if left.sequence != right.sequence { return left.sequence < right.sequence }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}

private struct LineageSequence: Hashable {
    let lineageID: LineageID
    let sequence: UInt
}
