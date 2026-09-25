import Foundation

public enum LifecycleContractError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidIdentifier(kind: String, value: String)
    case invalidReason
    case invalidSnapshot(String)
    case invalidArtifact(String)
    case conflictingSnapshot(String)
    case missingFinding(String)
    case missingSnapshot(String)

    public var description: String {
        switch self {
        case .invalidIdentifier(let kind, let value):
            "Invalid \(kind): \(value)"
        case .invalidReason:
            "Lifecycle reasons require a nonblank code and message."
        case .invalidSnapshot(let reason):
            "Invalid observation snapshot: \(reason)"
        case .invalidArtifact(let reason):
            "Invalid lifecycle artifact: \(reason)"
        case .conflictingSnapshot(let identifier):
            "Snapshot \(identifier) was already persisted with different content."
        case .missingFinding(let identifier):
            "Lifecycle artifact does not contain Finding \(identifier)."
        case .missingSnapshot(let identifier):
            "Lifecycle artifact does not contain snapshot \(identifier)."
        }
    }
}

public struct LifecycleReason: Codable, Equatable, Hashable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) throws {
        guard hasLifecycleContent(code), hasLifecycleContent(message) else {
            throw LifecycleContractError.invalidReason
        }
        self.code = code
        self.message = message
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                code: values.decode(String.self, forKey: .code),
                message: values.decode(String.self, forKey: .message)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }
}

func hasLifecycleContent(_ value: String) -> Bool {
    value.contains { !$0.isWhitespace }
        && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
}

func lifecycleReasonOrder(_ lhs: LifecycleReason, _ rhs: LifecycleReason) -> Bool {
    if lhs.code != rhs.code { return lhs.code < rhs.code }
    return lhs.message < rhs.message
}
