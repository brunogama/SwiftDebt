import Foundation
import SwiftDebtCore

public typealias LifecycleDigest = CompilerEvidenceDigest

public enum SourceWorkingTreeState: String, Codable, Equatable, Sendable {
    case clean
    case modified
}

public struct GitRevisionID: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw LifecycleContractError.invalidIdentifier(kind: "Git revision ID", value: rawValue)
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        do {
            try self.init(values.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: String(describing: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }

    private static func isValid(_ value: String) -> Bool {
        (value.utf8.count == 40 || value.utf8.count == 64)
            && value.utf8.allSatisfy { byte in
                switch byte {
                case 48...57, 97...102: true
                default: false
                }
            }
    }
}

public enum SnapshotSourceIdentity: Equatable, Sendable {
    case git(revision: GitRevisionID, workingTreeState: SourceWorkingTreeState, contentDigest: LifecycleDigest)
    case contentDigest(LifecycleDigest)
    case unavailable(LifecycleReason)

    public enum State: String, Codable, Sendable {
        case git
        case contentDigest = "content-digest"
        case unavailable
    }

    public var state: State {
        switch self {
        case .git: .git
        case .contentDigest: .contentDigest
        case .unavailable: .unavailable
        }
    }

    var supportsComparison: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

extension SnapshotSourceIdentity: Codable {
    private enum CodingKeys: String, CodingKey {
        case state
        case revision
        case workingTreeState
        case contentDigest
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(State.self, forKey: .state) {
        case .git:
            try Self.reject([.reason], in: values)
            self = .git(
                revision: try values.decode(GitRevisionID.self, forKey: .revision),
                workingTreeState: try values.decode(SourceWorkingTreeState.self, forKey: .workingTreeState),
                contentDigest: try values.decode(LifecycleDigest.self, forKey: .contentDigest)
            )
        case .contentDigest:
            try Self.reject([.revision, .workingTreeState, .reason], in: values)
            self = .contentDigest(try values.decode(LifecycleDigest.self, forKey: .contentDigest))
        case .unavailable:
            try Self.reject([.revision, .workingTreeState, .contentDigest], in: values)
            self = .unavailable(try values.decode(LifecycleReason.self, forKey: .reason))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(state, forKey: .state)
        switch self {
        case .git(let revision, let workingTreeState, let contentDigest):
            try values.encode(revision, forKey: .revision)
            try values.encode(workingTreeState, forKey: .workingTreeState)
            try values.encode(contentDigest, forKey: .contentDigest)
        case .contentDigest(let contentDigest):
            try values.encode(contentDigest, forKey: .contentDigest)
        case .unavailable(let reason):
            try values.encode(reason, forKey: .reason)
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
            debugDescription: "Source identity state cannot carry \(key.stringValue)."
        )
    }
}
