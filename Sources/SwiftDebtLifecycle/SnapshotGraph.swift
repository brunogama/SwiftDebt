public enum SnapshotParentBasis: Equatable, Sendable {
    case explicitPredecessor
    case gitDirectParent(GitRevisionID)
    case migratedSchemaOne

    enum Kind: String, Codable, Sendable {
        case explicitPredecessor = "explicit-predecessor"
        case gitDirectParent = "git-direct-parent"
        case migratedSchemaOne = "migrated-schema-1"
    }
}

extension SnapshotParentBasis: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case parentRevision
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .explicitPredecessor:
            self = .explicitPredecessor
        case .gitDirectParent:
            self = .gitDirectParent(
                try values.decode(GitRevisionID.self, forKey: .parentRevision)
            )
        case .migratedSchemaOne:
            self = .migratedSchemaOne
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .explicitPredecessor:
            try values.encode(Kind.explicitPredecessor, forKey: .kind)
        case .gitDirectParent(let revision):
            try values.encode(Kind.gitDirectParent, forKey: .kind)
            try values.encode(revision, forKey: .parentRevision)
        case .migratedSchemaOne:
            try values.encode(Kind.migratedSchemaOne, forKey: .kind)
        }
    }
}

public struct SnapshotParentEdge: Codable, Equatable, Sendable {
    public let childSnapshotID: SnapshotID
    public let parentSnapshotID: SnapshotID
    public let basis: SnapshotParentBasis

    package init(
        childSnapshotID: SnapshotID,
        parentSnapshotID: SnapshotID,
        basis: SnapshotParentBasis
    ) {
        self.childSnapshotID = childSnapshotID
        self.parentSnapshotID = parentSnapshotID
        self.basis = basis
    }
}

package struct LifecycleSnapshotIngestion: Sendable {
    package let snapshot: ObservationSnapshot
    package let parentEdge: SnapshotParentEdge?

    package init(snapshot: ObservationSnapshot, parentEdge: SnapshotParentEdge?) {
        self.snapshot = snapshot
        self.parentEdge = parentEdge
    }

    package static func explicit(_ snapshot: ObservationSnapshot) -> Self {
        let edge = snapshot.provenance.lineage.predecessorSnapshotID.map {
            SnapshotParentEdge(
                childSnapshotID: snapshot.id,
                parentSnapshotID: $0,
                basis: .explicitPredecessor
            )
        }
        return Self(snapshot: snapshot, parentEdge: edge)
    }
}

extension SnapshotParentEdge {
    static func order(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.childSnapshotID != rhs.childSnapshotID {
            return lhs.childSnapshotID.rawValue < rhs.childSnapshotID.rawValue
        }
        return lhs.parentSnapshotID.rawValue < rhs.parentSnapshotID.rawValue
    }
}

extension LifecycleArtifact {
    public var headSnapshotIDs: [SnapshotID] {
        let processed = Set(processedSnapshotIDs)
        let nonHeads = Set(
            snapshotParentEdges.compactMap { edge in
                processed.contains(edge.childSnapshotID) && processed.contains(edge.parentSnapshotID)
                    ? edge.parentSnapshotID : nil
            }
        )
        return processed.subtracting(nonHeads).sorted { $0.rawValue < $1.rawValue }
    }

    /// Compatibility projection for callers that previously enumerated linear
    /// heads. Snapshot IDs are the authoritative lineage selectors in schema 3.
    public var lineageHeads: [LineageHead] {
        headSnapshotIDs.compactMap { snapshotID in
            guard let snapshot = snapshot(id: snapshotID) else { return nil }
            return LineageHead(
                lineageID: snapshot.provenance.lineage.lineageID,
                snapshotID: snapshotID,
                sequence: snapshot.provenance.lineage.sequence
            )
        }
    }

    public func parentEdge(of snapshotID: SnapshotID) -> SnapshotParentEdge? {
        snapshotParentEdges.first { $0.childSnapshotID == snapshotID }
    }

    public func parentSnapshotID(of snapshotID: SnapshotID) -> SnapshotID? {
        parentEdge(of: snapshotID)?.parentSnapshotID
    }

    public func childSnapshotIDs(of snapshotID: SnapshotID) -> [SnapshotID] {
        snapshotParentEdges.compactMap {
            $0.parentSnapshotID == snapshotID ? $0.childSnapshotID : nil
        }.sorted { $0.rawValue < $1.rawValue }
    }

    public func isAncestor(_ ancestorID: SnapshotID, of descendantID: SnapshotID) -> Bool {
        guard snapshot(id: ancestorID) != nil, snapshot(id: descendantID) != nil else { return false }
        var cursor: SnapshotID? = descendantID
        var visited: Set<SnapshotID> = []
        while let current = cursor, visited.insert(current).inserted {
            if current == ancestorID { return true }
            cursor = parentSnapshotID(of: current)
        }
        return false
    }

    package func snapshotPath(through snapshotID: SnapshotID) throws -> [ObservationSnapshot] {
        guard let terminal = snapshot(id: snapshotID), processedSnapshotIDs.contains(snapshotID) else {
            throw LifecycleContractError.missingSnapshot(snapshotID.rawValue)
        }
        var reversed = [terminal]
        var cursor = terminal.id
        var visited: Set<SnapshotID> = [cursor]
        while let parentID = parentSnapshotID(of: cursor) {
            guard visited.insert(parentID).inserted, let parent = snapshot(id: parentID) else {
                throw LifecycleContractError.invalidArtifact("Snapshot graph contains a cycle or broken parent.")
            }
            reversed.append(parent)
            cursor = parentID
        }
        return reversed.reversed()
    }
}
