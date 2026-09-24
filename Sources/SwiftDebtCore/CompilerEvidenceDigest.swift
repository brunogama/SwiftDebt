/// Validation failures at the public compiler-evidence contract boundary.
public enum CompilerEvidenceContractError: Error, Equatable, Sendable {
    case emptyEvidenceIssueCode
    case emptyEvidenceIssueMessage
    case emptySourceRevision
    case invalidSHA256Digest(String)
}

/// A validated digest used to identify build inputs or analyzed source content.
public struct CompilerEvidenceDigest: Equatable, Sendable {
    public enum Algorithm: String, Codable, Sendable {
        case sha256
    }

    public let algorithm: Algorithm
    public let value: String

    public init(algorithm: Algorithm = .sha256, value: String) throws {
        guard Self.isValidSHA256(value) else {
            throw CompilerEvidenceContractError.invalidSHA256Digest(value)
        }
        self.algorithm = algorithm
        self.value = value
    }

    private static func isValidSHA256(_ value: String) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy { byte in
                switch byte {
                case 48...57, 97...102: true
                default: false
                }
            }
    }
}

extension CompilerEvidenceDigest: Codable {
    private enum CodingKeys: String, CodingKey {
        case algorithm
        case value
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let algorithm = try values.decode(Algorithm.self, forKey: .algorithm)
        let value = try values.decode(String.self, forKey: .value)
        do {
            try self.init(algorithm: algorithm, value: value)
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: values,
                debugDescription: "SHA-256 evidence digests must contain 64 lowercase hexadecimal characters."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(algorithm, forKey: .algorithm)
        try values.encode(value, forKey: .value)
    }
}
