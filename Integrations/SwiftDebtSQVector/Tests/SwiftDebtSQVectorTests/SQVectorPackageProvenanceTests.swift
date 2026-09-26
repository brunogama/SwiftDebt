#if canImport(SQVector)
    import Foundation
    import SQVector
    import SwiftDebtSQVector
    import Testing

    @Suite("SQVector package provenance")
    struct SQVectorPackageProvenanceTests {
        @Test("binds runtime provenance to the exact dependency revision")
        func pinnedIdentity() throws {
            let pinned = SQVectorPackageIdentity.pinned
            #expect(pinned.version == .unavailable)
            #expect(pinned.revision == "aafd9ae601826112978127c7cb611c94ab8a2e06")
            #expect(try makeIdentity().sqVectorPackage == pinned)

            let manifestURL = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Package.swift")
            let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
            #expect(manifest.contains("revision: \"\(pinned.revision)\""))
        }

        @Test("rejects invalid package identities")
        func validation() {
            #expect(
                throws: LocalCandidateIndexError.emptyIdentityField(.sqVectorPackageVersion)
            ) {
                _ = try makeSQVectorPackageIdentity(version: .available(" "))
            }
            #expect(
                throws: LocalCandidateIndexError.invalidSQVectorPackageRevision("main")
            ) {
                _ = try makeSQVectorPackageIdentity(revision: "main")
            }
        }

        @Test("rejects decoded package claims before creating storage")
        func rejectsDecodedPackageClaim() async throws {
            let expected = try makeIdentity()
            let claimedPackage = try makeSQVectorPackageIdentity(
                revision: String(repeating: "d", count: 40)
            )
            let encoded = try JSONEncoder().encode(expected)
            var object = try #require(
                JSONSerialization.jsonObject(with: encoded) as? [String: Any]
            )
            var package = try #require(
                object["sqVectorPackage"] as? [String: Any]
            )
            package["revision"] = claimedPackage.revision
            object["sqVectorPackage"] = package
            let decoded = try JSONDecoder().decode(
                LocalCandidateIndexIdentity.self,
                from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            )
            #expect(decoded.sqVectorPackage == claimedPackage)

            let url = temporaryIndexURL()
            defer { removeIndexFiles(at: url) }
            await #expect(
                throws: LocalCandidateIndexError.incompatibleIndex(
                    expected: expected,
                    actual: decoded
                )
            ) {
                _ = try await SQVectorExactCandidateIndex.open(at: url, identity: decoded)
            }
            #expect(FileManager.default.fileExists(atPath: url.path) == false)
        }

        @Test("rejects persisted package version and revision mismatches")
        func compatibility() async throws {
            let pinned = SQVectorPackageIdentity.pinned
            let cases = [
                (
                    sql: """
                    UPDATE swiftdebt_index_manifest
                    SET sqvector_package_version_state = 'available',
                        sqvector_package_version_value = 'v1.0.0'
                    WHERE singleton = 1
                    """,
                    expected: try makeSQVectorPackageIdentity(version: .available("v1.0.0"))
                ),
                (
                    sql: """
                    UPDATE swiftdebt_index_manifest
                    SET sqvector_package_revision = '\(String(repeating: "d", count: 40))'
                    WHERE singleton = 1
                    """,
                    expected: try makeSQVectorPackageIdentity(
                        revision: String(repeating: "d", count: 40)
                    )
                ),
            ]

            for mismatch in cases {
                let url = temporaryIndexURL()
                defer { removeIndexFiles(at: url) }
                let identity = try makeIdentity()
                let initial = try await SQVectorExactCandidateIndex.open(
                    at: url,
                    identity: identity
                )
                try await initial.close()

                let storage = try await SQLiteDatabase.open(at: url.path)
                try await storage.execute(sql: mismatch.sql)
                try await storage.close()

                do {
                    let reopened = try await SQVectorExactCandidateIndex.open(
                        at: url,
                        identity: identity
                    )
                    try await reopened.close()
                    Issue.record("Expected persisted package provenance mismatch")
                } catch let error as LocalCandidateIndexError {
                    guard case .incompatibleIndex(let expected, let actual) = error else {
                        Issue.record("Expected incompatible index, got \(error)")
                        continue
                    }
                    #expect(expected.sqVectorPackage == pinned)
                    #expect(actual.sqVectorPackage == mismatch.expected)
                }
            }
        }

        @Test("rejects the draft schema v2 package-version layout")
        func rejectsDraftSchemaV2Storage() async throws {
            let url = temporaryIndexURL()
            defer { removeIndexFiles(at: url) }
            let storage = try await SQLiteDatabase.open(at: url.path)
            try await storage.execute(
                sql: """
                    CREATE TABLE swiftdebt_index_manifest (
                        singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
                        schema_version INTEGER NOT NULL,
                        namespace TEXT NOT NULL,
                        provider TEXT NOT NULL,
                        provider_version_state TEXT NOT NULL,
                        provider_version_value TEXT,
                        model TEXT NOT NULL,
                        model_revision_state TEXT NOT NULL,
                        model_revision_value TEXT,
                        dimensions INTEGER NOT NULL,
                        metric TEXT NOT NULL,
                        projection_revision TEXT NOT NULL,
                        source_snapshot_digest_algorithm TEXT NOT NULL,
                        source_snapshot_digest_value TEXT NOT NULL,
                        sqvector_package_version TEXT NOT NULL,
                        sqvector_package_revision TEXT NOT NULL
                    )
                    """
            )
            try await storage.execute(
                sql: """
                    INSERT INTO swiftdebt_index_manifest (
                        singleton, schema_version, namespace, provider,
                        provider_version_state, provider_version_value,
                        model, model_revision_state, model_revision_value,
                        dimensions, metric, projection_revision,
                        source_snapshot_digest_algorithm, source_snapshot_digest_value,
                        sqvector_package_version, sqvector_package_revision
                    ) VALUES (
                        1, 2, 'snapshot', 'provider', 'available', 'v1',
                        'model', 'available', 'r1', 2, 'cosine', 'projection-v1',
                        'sha256', '\(String(repeating: "a", count: 64))',
                        'local-draft', '\(String(repeating: "b", count: 40))'
                    )
                    """
            )
            try await storage.close()

            await #expect(throws: LocalCandidateIndexError.corruptStorage) {
                _ = try await SQVectorExactCandidateIndex.open(
                    at: url,
                    identity: makeIdentity()
                )
            }

            let unchanged = try await SQLiteDatabase.open(at: url.path)
            let columns = try await unchanged.fetchRows(
                sql: "PRAGMA table_info(swiftdebt_index_manifest)"
            )
            let names = columns.compactMap { $0["name"]?.stringValue }
            #expect(names.contains("sqvector_package_version"))
            #expect(names.contains("sqvector_package_version_state") == false)
            try await unchanged.close()
        }
    }
#endif
