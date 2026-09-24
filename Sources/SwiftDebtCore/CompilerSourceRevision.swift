/// Whether a version-controlled source snapshot included local modifications.
public enum CompilerSourceWorkingTreeState: String, Codable, Sendable {
    case clean
    case modified
}

/// A nonempty version-control revision identifier.
public struct CompilerRevisionIdentifier: Equatable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        guard !value.isEmpty else {
            throw CompilerEvidenceContractError.emptySourceRevision
        }
        self.value = value
    }
}

extension CompilerRevisionIdentifier: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            try self.init(value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "A version-control source revision cannot be empty."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(self.value)
    }
}

/// The analyzed source snapshot, including honest states for archives and missing identity.
public enum CompilerSourceRevision: Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case versionControl = "version-control"
        case contentDigest = "content-digest"
        case unavailable
    }

    case versionControl(
        revision: CompilerRevisionIdentifier,
        workingTreeState: CompilerSourceWorkingTreeState,
        contentDigest: CompilerEvidenceDigest
    )
    case contentDigest(CompilerEvidenceDigest)
    case unavailable(CompilerEvidenceIssue)

    public var state: State {
        switch self {
        case .versionControl: .versionControl
        case .contentDigest: .contentDigest
        case .unavailable: .unavailable
        }
    }
}

extension CompilerSourceRevision: Codable {
    private enum CodingKeys: String, CodingKey {
        case state
        case revision
        case workingTreeState
        case contentDigest
        case issue
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let state = try values.decode(State.self, forKey: .state)
        switch state {
        case .versionControl:
            try Self.reject([.issue], in: values)
            self = .versionControl(
                revision: try values.decode(CompilerRevisionIdentifier.self, forKey: .revision),
                workingTreeState: try values.decode(CompilerSourceWorkingTreeState.self, forKey: .workingTreeState),
                contentDigest: try values.decode(CompilerEvidenceDigest.self, forKey: .contentDigest)
            )
        case .contentDigest:
            try Self.reject([.revision, .workingTreeState, .issue], in: values)
            self = .contentDigest(try values.decode(CompilerEvidenceDigest.self, forKey: .contentDigest))
        case .unavailable:
            try Self.reject([.revision, .workingTreeState, .contentDigest], in: values)
            self = .unavailable(try values.decode(CompilerEvidenceIssue.self, forKey: .issue))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(state, forKey: .state)
        switch self {
        case .versionControl(let revision, let workingTreeState, let contentDigest):
            try values.encode(revision, forKey: .revision)
            try values.encode(workingTreeState, forKey: .workingTreeState)
            try values.encode(contentDigest, forKey: .contentDigest)
        case .contentDigest(let contentDigest):
            try values.encode(contentDigest, forKey: .contentDigest)
        case .unavailable(let issue):
            try values.encode(issue, forKey: .issue)
        }
    }

    private static func reject(
        _ keys: [CodingKeys],
        in values: KeyedDecodingContainer<CodingKeys>
    ) throws {
        guard let key = keys.first(where: values.contains) else { return }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: values,
            debugDescription:
                "Source revision state \(try values.decode(State.self, forKey: .state).rawValue) cannot carry \(key.stringValue)."
        )
    }
}
