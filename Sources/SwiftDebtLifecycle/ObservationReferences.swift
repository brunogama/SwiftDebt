import SwiftDebtCore

public struct SnapshotRule: Equatable, Hashable, Sendable {
    public let identity: RuleIdentity
    public let semanticRevision: SemanticRevision
    public let compatibilityDeclarations: [SemanticCompatibilityDeclaration]
    public let configurationCompatibilityDeclarations: [ConfigurationCompatibilityDeclaration]

    public init(identity: RuleIdentity, semanticRevision: SemanticRevision) {
        self.identity = identity
        self.semanticRevision = semanticRevision
        self.compatibilityDeclarations = []
        self.configurationCompatibilityDeclarations = []
    }

    package init(
        identity: RuleIdentity,
        semanticRevision: SemanticRevision,
        compatibilityDeclarations: [SemanticCompatibilityDeclaration],
        configurationCompatibilityDeclarations: [ConfigurationCompatibilityDeclaration]
    ) throws {
        self.identity = identity
        self.semanticRevision = semanticRevision
        self.compatibilityDeclarations = compatibilityDeclarations.sorted {
            $0.fromRevision.rawValue < $1.fromRevision.rawValue
        }
        self.configurationCompatibilityDeclarations = configurationCompatibilityDeclarations.sorted {
            $0.canonicalOrderKey < $1.canonicalOrderKey
        }
        try validateCompatibility()
    }
}

extension SnapshotRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case namespace
        case id
        case semanticRevision
        case compatibilityDeclarations
        case configurationCompatibilityDeclarations
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let namespaceValue = try values.decode(String.self, forKey: .namespace)
        let idValue = try values.decode(String.self, forKey: .id)
        let revisionValue = try values.decode(UInt.self, forKey: .semanticRevision)
        guard
            let namespace = RuleNamespace(namespaceValue),
            let id = RuleID(idValue),
            let semanticRevision = SemanticRevision(revisionValue)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: values,
                debugDescription: "Snapshot rules require a valid identity and positive semantic revision."
            )
        }
        let declarations =
            try values.decodeIfPresent(
                [SemanticCompatibilityDeclaration].self,
                forKey: .compatibilityDeclarations
            ) ?? []
        let canonicalDeclarations = declarations.sorted {
            $0.fromRevision.rawValue < $1.fromRevision.rawValue
        }
        guard declarations == canonicalDeclarations else {
            throw DecodingError.dataCorruptedError(
                forKey: .compatibilityDeclarations,
                in: values,
                debugDescription: "Rule compatibility declarations must use canonical revision order."
            )
        }
        let configurationDeclarations =
            try values.decodeIfPresent(
                [ConfigurationCompatibilityDeclaration].self,
                forKey: .configurationCompatibilityDeclarations
            ) ?? []
        let canonicalConfigurationDeclarations = configurationDeclarations.sorted {
            $0.canonicalOrderKey < $1.canonicalOrderKey
        }
        guard configurationDeclarations == canonicalConfigurationDeclarations else {
            throw DecodingError.dataCorruptedError(
                forKey: .configurationCompatibilityDeclarations,
                in: values,
                debugDescription: "Configuration compatibility declarations must use canonical order."
            )
        }
        do {
            try self.init(
                identity: RuleIdentity(namespace: namespace, id: id),
                semanticRevision: semanticRevision,
                compatibilityDeclarations: declarations,
                configurationCompatibilityDeclarations: configurationDeclarations
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .compatibilityDeclarations,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(identity.namespace.rawValue, forKey: .namespace)
        try values.encode(identity.id.rawValue, forKey: .id)
        try values.encode(semanticRevision.rawValue, forKey: .semanticRevision)
        if !compatibilityDeclarations.isEmpty {
            try values.encode(compatibilityDeclarations, forKey: .compatibilityDeclarations)
        }
        if !configurationCompatibilityDeclarations.isEmpty {
            try values.encode(
                configurationCompatibilityDeclarations,
                forKey: .configurationCompatibilityDeclarations
            )
        }
    }

    private func validateCompatibility() throws {
        guard Set(compatibilityDeclarations.map(\.fromRevision)).count == compatibilityDeclarations.count,
            compatibilityDeclarations.allSatisfy({
                $0.fromRevision.rawValue < semanticRevision.rawValue
            })
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Rule compatibility must point from unique earlier Semantic Revisions."
            )
        }
        let configurationClaimKeys = configurationCompatibilityDeclarations.flatMap { declaration in
            declaration.supportedClaims.map {
                SnapshotConfigurationClaimKey(revision: declaration.fromRevision, claim: $0)
            }
        }
        guard Set(configurationClaimKeys).count == configurationClaimKeys.count,
            configurationCompatibilityDeclarations.allSatisfy({
                $0.fromRevision.rawValue <= semanticRevision.rawValue
            })
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Rule configuration compatibility must use unique claims from the current or earlier revisions."
            )
        }
        for declaration in configurationCompatibilityDeclarations
        where declaration.fromRevision != semanticRevision {
            guard
                let semantic = compatibilityDeclarations.first(where: {
                    $0.fromRevision == declaration.fromRevision
                }),
                declaration.supportedClaims.allSatisfy(semantic.supportedClaims.contains)
            else {
                throw LifecycleContractError.invalidSnapshot(
                    "Cross-revision configuration compatibility requires matching semantic compatibility."
                )
            }
        }
    }
}

private struct SnapshotConfigurationClaimKey: Hashable {
    let revision: SemanticRevision
    let claim: SemanticCompatibilityClaim
}

public struct SnapshotLocation: Codable, Equatable, Hashable, Sendable {
    public let sourcePath: SourcePath
    public let line: Int
    public let column: Int

    public init(sourcePath: SourcePath, line: Int, column: Int) throws {
        guard line > 0, column > 0 else {
            throw LifecycleContractError.invalidSnapshot("Detection locations require positive line and column values.")
        }
        self.sourcePath = sourcePath
        self.line = line
        self.column = column
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case line
        case column
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                sourcePath: SourcePath(values.decode(String.self, forKey: .sourcePath)),
                line: values.decode(Int.self, forKey: .line),
                column: values.decode(Int.self, forKey: .column)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .sourcePath,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sourcePath.rawValue, forKey: .sourcePath)
        try values.encode(line, forKey: .line)
        try values.encode(column, forKey: .column)
    }
}

struct AtomicObservationKey: Hashable {
    let rule: SnapshotRule
    let sourcePath: SourcePath
}
