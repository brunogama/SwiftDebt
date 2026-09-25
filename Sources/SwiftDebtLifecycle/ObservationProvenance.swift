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
    public let effectiveConfiguration: LifecycleEffectiveConfiguration?
    public let capabilities: [SnapshotCapability]
    public let engineVersion: String
    public let lineage: LineagePosition
    public let sourceSelection: SourceSelectionEvidence?
    public let sourceRenames: [SourceRenameEvidence]
    public let sourceDeletions: [SourceDeletionEvidence]

    public init(
        sourceIdentity: SnapshotSourceIdentity,
        scope: ObservationScope,
        configurationFingerprint: LifecycleDigest,
        capabilities: [SnapshotCapability] = [],
        engineVersion: String,
        lineage: LineagePosition,
        sourceSelection: SourceSelectionEvidence? = nil,
        sourceRenames: [SourceRenameEvidence] = [],
        sourceDeletions: [SourceDeletionEvidence] = []
    ) throws {
        try self.init(
            sourceIdentity: sourceIdentity,
            scope: scope,
            configurationFingerprint: configurationFingerprint,
            effectiveConfiguration: nil,
            capabilities: capabilities,
            engineVersion: engineVersion,
            lineage: lineage,
            sourceSelection: sourceSelection,
            sourceRenames: sourceRenames,
            sourceDeletions: sourceDeletions
        )
    }

    package init(
        sourceIdentity: SnapshotSourceIdentity,
        scope: ObservationScope,
        configurationFingerprint: LifecycleDigest,
        effectiveConfiguration: LifecycleEffectiveConfiguration,
        capabilities: [SnapshotCapability] = [],
        engineVersion: String,
        lineage: LineagePosition,
        sourceSelection: SourceSelectionEvidence? = nil,
        sourceRenames: [SourceRenameEvidence] = [],
        sourceDeletions: [SourceDeletionEvidence] = []
    ) throws {
        try self.init(
            sourceIdentity: sourceIdentity,
            scope: scope,
            configurationFingerprint: configurationFingerprint,
            effectiveConfiguration: Optional(effectiveConfiguration),
            capabilities: capabilities,
            engineVersion: engineVersion,
            lineage: lineage,
            sourceSelection: sourceSelection,
            sourceRenames: sourceRenames,
            sourceDeletions: sourceDeletions
        )
    }

    private init(
        sourceIdentity: SnapshotSourceIdentity,
        scope: ObservationScope,
        configurationFingerprint: LifecycleDigest,
        effectiveConfiguration: LifecycleEffectiveConfiguration?,
        capabilities: [SnapshotCapability],
        engineVersion: String,
        lineage: LineagePosition,
        sourceSelection: SourceSelectionEvidence?,
        sourceRenames: [SourceRenameEvidence],
        sourceDeletions: [SourceDeletionEvidence]
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
        let sortedRenames = sourceRenames.sorted(by: sourceRenameOrder)
        let sortedDeletions = sourceDeletions.sorted(by: sourceDeletionOrder)
        guard Set(sortedRenames.map(\.priorSourcePath)).count == sortedRenames.count,
            Set(sortedRenames.map(\.currentSourcePath)).count == sortedRenames.count
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Git rename evidence must map unique prior and current SourceUnit paths."
            )
        }
        guard Set(sortedDeletions.map(\.priorSourcePath)).count == sortedDeletions.count else {
            throw LifecycleContractError.invalidSnapshot(
                "Git deletion evidence must reference unique prior SourceUnit paths."
            )
        }
        guard
            Set(sortedRenames.map(\.priorSourcePath)).isDisjoint(
                with: Set(sortedDeletions.map(\.priorSourcePath))
            )
        else {
            throw LifecycleContractError.invalidSnapshot(
                "A prior SourceUnit cannot be both renamed and deleted by one Git edge."
            )
        }
        if !sortedRenames.isEmpty || !sortedDeletions.isEmpty {
            guard case .git = sourceIdentity else {
                throw LifecycleContractError.invalidSnapshot(
                    "Source rename and deletion evidence require Git source identity."
                )
            }
        }
        if let effectiveConfiguration {
            guard try effectiveConfiguration.fingerprint() == configurationFingerprint else {
                throw LifecycleContractError.invalidSnapshot(
                    "Effective configuration does not match its canonical fingerprint."
                )
            }
            if let sourceSelection {
                guard sourceSelection.kind == effectiveConfiguration.sourceSelectionKind else {
                    throw LifecycleContractError.invalidSnapshot(
                        "Effective configuration and source selection kinds disagree."
                    )
                }
            }
        }
        self.sourceIdentity = sourceIdentity
        self.scope = scope
        self.configurationFingerprint = configurationFingerprint
        self.effectiveConfiguration = effectiveConfiguration
        self.capabilities = sortedCapabilities
        self.engineVersion = engineVersion
        self.lineage = lineage
        self.sourceSelection = sourceSelection
        self.sourceRenames = sortedRenames
        self.sourceDeletions = sortedDeletions
    }

    private enum CodingKeys: String, CodingKey {
        case sourceIdentity
        case scope
        case configurationFingerprint
        case effectiveConfiguration
        case capabilities
        case engineVersion
        case lineage
        case sourceSelection
        case sourceRenames
        case sourceDeletions
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sourceIdentity: values.decode(SnapshotSourceIdentity.self, forKey: .sourceIdentity),
                scope: values.decode(ObservationScope.self, forKey: .scope),
                configurationFingerprint: values.decode(LifecycleDigest.self, forKey: .configurationFingerprint),
                effectiveConfiguration: values.decodeIfPresent(
                    LifecycleEffectiveConfiguration.self,
                    forKey: .effectiveConfiguration
                ),
                capabilities: values.decode([SnapshotCapability].self, forKey: .capabilities),
                engineVersion: values.decode(String.self, forKey: .engineVersion),
                lineage: values.decode(LineagePosition.self, forKey: .lineage),
                sourceSelection: values.decodeIfPresent(
                    SourceSelectionEvidence.self,
                    forKey: .sourceSelection
                ),
                sourceRenames: values.decodeIfPresent(
                    [SourceRenameEvidence].self,
                    forKey: .sourceRenames
                ) ?? [],
                sourceDeletions: values.decodeIfPresent(
                    [SourceDeletionEvidence].self,
                    forKey: .sourceDeletions
                ) ?? []
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .sourceIdentity,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }
}
