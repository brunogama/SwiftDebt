import SwiftDebtCore

public struct SnapshotRule: Equatable, Hashable, Sendable {
    public let identity: RuleIdentity
    public let semanticRevision: SemanticRevision

    public init(identity: RuleIdentity, semanticRevision: SemanticRevision) {
        self.identity = identity
        self.semanticRevision = semanticRevision
    }
}

extension SnapshotRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case namespace
        case id
        case semanticRevision
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
        self.init(
            identity: RuleIdentity(namespace: namespace, id: id),
            semanticRevision: semanticRevision
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(identity.namespace.rawValue, forKey: .namespace)
        try values.encode(identity.id.rawValue, forKey: .id)
        try values.encode(semanticRevision.rawValue, forKey: .semanticRevision)
    }
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
