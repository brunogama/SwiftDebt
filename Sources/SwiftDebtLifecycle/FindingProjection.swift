public struct FindingProjection: Codable, Equatable, Sendable {
    public let snapshotID: SnapshotID
    public let finding: Finding

    public var lifecycleState: FindingLifecycleState { finding.lifecycleState }
    public var evidenceState: FindingEvidenceState { finding.evidenceState }

    init(snapshotID: SnapshotID, finding: Finding) {
        self.snapshotID = snapshotID
        self.finding = finding
    }
}

extension LifecycleArtifact {
    public func findingProjection(
        id findingID: FindingID,
        at snapshotID: SnapshotID
    ) throws -> FindingProjection? {
        guard let finding = finding(id: findingID) else {
            throw LifecycleContractError.missingFinding(findingID.rawValue)
        }
        return try findingProjection(finding, at: snapshotID)
    }

    public func findingProjections(at snapshotID: SnapshotID) throws -> [FindingProjection] {
        guard processedSnapshotIDs.contains(snapshotID) else {
            throw LifecycleContractError.missingSnapshot(snapshotID.rawValue)
        }
        return try findings.compactMap { try findingProjection($0, at: snapshotID) }
            .sorted { $0.finding.id.rawValue < $1.finding.id.rawValue }
    }

    package func findingProjection(
        _ finding: Finding,
        at snapshotID: SnapshotID
    ) throws -> FindingProjection? {
        let path = try snapshotPath(through: snapshotID)
        let positionBySnapshotID = Dictionary(
            uniqueKeysWithValues: path.enumerated().map { ($0.element.id, $0.offset) }
        )
        let eligible = finding.events.compactMap { event -> (Int, LifecycleEvent)? in
            guard let position = positionBySnapshotID[event.snapshotID] else { return nil }
            return (position, event)
        }
        guard
            let terminal = eligible.max(by: { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1.id.rawValue < rhs.1.id.rawValue : lhs.0 < rhs.0
            })?.1
        else {
            return nil
        }
        let projected = try finding.projected(through: terminal.id)
        let pathIDs = Set(path.map(\.id))
        guard projected.events.allSatisfy({ pathIDs.contains($0.snapshotID) }) else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) event basis crosses sibling snapshot branches."
            )
        }
        return FindingProjection(snapshotID: snapshotID, finding: projected)
    }

    package func parentFindingProjections(of snapshotID: SnapshotID) throws -> [FindingProjection] {
        guard let parentID = parentSnapshotID(of: snapshotID) else { return [] }
        return try findingProjections(at: parentID)
    }
}
