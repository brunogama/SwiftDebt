import Foundation

public enum LocalCandidateDigestAlgorithm: String, Codable, Sendable {
    case sha256
}

public struct LocalCandidateSourceSnapshotDigest: Codable, Equatable, Sendable {
    public let algorithm: LocalCandidateDigestAlgorithm
    public let value: String

    public init(sha256 value: String) throws {
        guard isHexadecimal(value, allowedLengths: [64]) else {
            throw LocalCandidateIndexError.invalidSourceSnapshotDigest(value)
        }
        algorithm = .sha256
        self.value = value.lowercased()
    }

    init(algorithm: LocalCandidateDigestAlgorithm, value: String) throws {
        switch algorithm {
        case .sha256:
            try self.init(sha256: value)
        }
    }
}

public struct SQVectorPackageIdentity: Codable, Equatable, Sendable {
    public static let pinned = Self(
        version: .unavailable,
        validatedRevision: "aafd9ae601826112978127c7cb611c94ab8a2e06"
    )

    public let version: LocalCandidateVersionIdentity
    public let revision: String

    public init(version: LocalCandidateVersionIdentity, revision: String) throws {
        try Self.validate(version: version, revision: revision)
        self.version = version
        self.revision = revision.lowercased()
    }

    private init(
        version: LocalCandidateVersionIdentity,
        validatedRevision: String
    ) {
        self.version = version
        revision = validatedRevision
    }

    func validate() throws {
        try Self.validate(version: version, revision: revision)
    }

    private static func validate(
        version: LocalCandidateVersionIdentity,
        revision: String
    ) throws {
        try version.validate(field: .sqVectorPackageVersion)
        guard isHexadecimal(revision, allowedLengths: [40, 64]) else {
            throw LocalCandidateIndexError.invalidSQVectorPackageRevision(revision)
        }
    }
}

private func isHexadecimal(_ value: String, allowedLengths: Set<Int>) -> Bool {
    allowedLengths.contains(value.utf8.count)
        && value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
}
