import Foundation
import SwiftDebtCore

struct RepositorySyntaxCacheDocument: Codable, Equatable, Sendable {
    static let reportKind = "swiftdebt-repository-syntax-cache-store"
    static let schemaVersion = 1

    let reportKind: String
    let schemaVersion: Int
    let integrityDigest: RepositoryDigest
    let sourceSnapshotDigest: RepositoryDigest
    let compatibility: RepositorySyntaxCacheCompatibility
    let entries: [RepositorySyntaxCacheEntry]

    init(
        sourceSnapshotDigest: RepositoryDigest,
        compatibility: RepositorySyntaxCacheCompatibility,
        entries: [RepositorySyntaxCacheEntry]
    ) throws {
        let orderedEntries = entries.sorted { $0.path < $1.path }
        self.reportKind = Self.reportKind
        self.schemaVersion = Self.schemaVersion
        self.integrityDigest = try Self.makeIntegrityDigest(
            sourceSnapshotDigest: sourceSnapshotDigest,
            compatibility: compatibility,
            entries: orderedEntries
        )
        self.sourceSnapshotDigest = sourceSnapshotDigest
        self.compatibility = compatibility
        self.entries = orderedEntries
    }

    func validate() throws {
        guard reportKind == Self.reportKind else {
            throw RepositorySyntaxCacheValidationError.invalidReportKind
        }
        guard schemaVersion == Self.schemaVersion else {
            throw RepositorySyntaxCacheValidationError.unsupportedSchema
        }
        try compatibility.validateCanonicalForm()
        guard
            integrityDigest
                == (try Self.makeIntegrityDigest(
                    sourceSnapshotDigest: sourceSnapshotDigest,
                    compatibility: compatibility,
                    entries: entries
                ))
        else {
            throw RepositorySyntaxCacheValidationError.integrityMismatch
        }
        guard entries == entries.sorted(by: { $0.path < $1.path }),
            Set(entries.map(\.path)).count == entries.count
        else {
            throw RepositorySyntaxCacheValidationError.noncanonicalEntries
        }
        for entry in entries {
            try entry.validate()
        }
    }

    private static func makeIntegrityDigest(
        sourceSnapshotDigest: RepositoryDigest,
        compatibility: RepositorySyntaxCacheCompatibility,
        entries: [RepositorySyntaxCacheEntry]
    ) throws -> RepositoryDigest {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = RepositorySyntaxCacheIntegrityPayload(
            sourceSnapshotDigest: sourceSnapshotDigest,
            compatibility: compatibility,
            entries: entries
        )
        var hasher = RepositorySHA256()
        hasher.update(try encoder.encode(payload))
        return try RepositoryDigest(value: hasher.finalizeHex())
    }
}

private struct RepositorySyntaxCacheIntegrityPayload: Encodable {
    let sourceSnapshotDigest: RepositoryDigest
    let compatibility: RepositorySyntaxCacheCompatibility
    let entries: [RepositorySyntaxCacheEntry]
}

struct RepositorySyntaxCacheHeader: Decodable {
    let reportKind: String
    let schemaVersion: Int
}
