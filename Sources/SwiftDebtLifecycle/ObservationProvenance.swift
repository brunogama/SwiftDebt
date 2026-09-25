import SwiftDebtCore

public struct LineagePosition: Codable, Equatable, Sendable {
    public let lineageID: LineageID
    public let sequence: UInt
    public let predecessorSnapshotID: SnapshotID?

    public init(lineageID: LineageID, sequence: UInt, predecessorSnapshotID: SnapshotID? = nil) throws {
        guard sequence > 0 else {
            throw LifecycleContractError.invalidSnapshot("Lineage sequence must be positive.")
        }
        guard (sequence == 1) == (predecessorSnapshotID == nil) else {
            throw LifecycleContractError.invalidSnapshot(
                "Lineage sequence 1 must have no predecessor, and later positions require one."
            )
        }
        self.lineageID = lineageID
        self.sequence = sequence
        self.predecessorSnapshotID = predecessorSnapshotID
    }
}

public struct SnapshotProvenance: Codable, Equatable, Sendable {
    public let sourceIdentity: SnapshotSourceIdentity
    public let scope: ObservationScope
    public let configurationFingerprint: LifecycleDigest
    public let capabilities: [SnapshotCapability]
    public let engineVersion: String
    public let lineage: LineagePosition

    public init(
        sourceIdentity: SnapshotSourceIdentity,
        scope: ObservationScope,
        configurationFingerprint: LifecycleDigest,
        capabilities: [SnapshotCapability] = [],
        engineVersion: String,
        lineage: LineagePosition
    ) throws {
        guard hasLifecycleContent(engineVersion) else {
            throw LifecycleContractError.invalidSnapshot(
                "Engine version must be nonblank."
            )
        }
        let sortedCapabilities = capabilities.sorted { $0.name < $1.name }
        guard Set(sortedCapabilities.map(\.name)).count == sortedCapabilities.count else {
            throw LifecycleContractError.invalidSnapshot("Capability names must be unique.")
        }
        self.sourceIdentity = sourceIdentity
        self.scope = scope
        self.configurationFingerprint = configurationFingerprint
        self.capabilities = sortedCapabilities
        self.engineVersion = engineVersion
        self.lineage = lineage
    }
}
