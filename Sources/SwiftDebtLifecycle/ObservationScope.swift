public enum ObservationScope: Equatable, Sendable {
    case repository
    case partial(LifecycleReason)

    public var isCompleteRepository: Bool {
        if case .repository = self { return true }
        return false
    }
}

extension ObservationScope: Codable {
    private enum Kind: String, Codable {
        case repository
        case partial
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .repository:
            guard !values.contains(.reason) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .reason,
                    in: values,
                    debugDescription: "Repository scope cannot carry a limiting reason."
                )
            }
            self = .repository
        case .partial:
            self = .partial(try values.decode(LifecycleReason.self, forKey: .reason))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .repository:
            try values.encode(Kind.repository, forKey: .kind)
        case .partial(let reason):
            try values.encode(Kind.partial, forKey: .kind)
            try values.encode(reason, forKey: .reason)
        }
    }
}

public enum SnapshotCapabilityState: Equatable, Sendable {
    case available
    case unavailable(LifecycleReason)
    case ambiguous(LifecycleReason)

    var supportsComparison: Bool {
        if case .available = self { return true }
        return false
    }
}

extension SnapshotCapabilityState: Codable {
    private enum Kind: String, Codable {
        case available
        case unavailable
        case ambiguous
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .available:
            guard !values.contains(.reason) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .reason,
                    in: values,
                    debugDescription: "An available capability cannot carry a reason."
                )
            }
            self = .available
        case .unavailable:
            self = .unavailable(try values.decode(LifecycleReason.self, forKey: .reason))
        case .ambiguous:
            self = .ambiguous(try values.decode(LifecycleReason.self, forKey: .reason))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .available:
            try values.encode(Kind.available, forKey: .kind)
        case .unavailable(let reason):
            try values.encode(Kind.unavailable, forKey: .kind)
            try values.encode(reason, forKey: .reason)
        case .ambiguous(let reason):
            try values.encode(Kind.ambiguous, forKey: .kind)
            try values.encode(reason, forKey: .reason)
        }
    }
}

public struct SnapshotCapability: Codable, Equatable, Sendable {
    public let name: String
    public let state: SnapshotCapabilityState

    public init(name: String, state: SnapshotCapabilityState) throws {
        guard hasLifecycleContent(name) else {
            throw LifecycleContractError.invalidIdentifier(kind: "capability name", value: name)
        }
        self.name = name
        self.state = state
    }
}
