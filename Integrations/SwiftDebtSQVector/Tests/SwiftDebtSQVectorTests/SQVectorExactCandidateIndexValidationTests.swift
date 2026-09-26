#if canImport(SQVector)
    import SQVector
    import SwiftDebtSQVector
    import Testing

    @Suite("SQVector exact candidate index validation")
    struct SQVectorExactCandidateIndexValidationTests {
        @Test("rejects incompatible persisted identities")
        func compatibility() async throws {
            let url = temporaryIndexURL()
            defer { removeIndexFiles(at: url) }
            let baseline = try makeIdentity()
            let initial = try await SQVectorExactCandidateIndex.open(at: url, identity: baseline)
            try await initial.close()

            let incompatible = [
                try makeIdentity(namespace: "other"),
                try makeIdentity(provider: "other"),
                try makeIdentity(providerVersion: .available("other")),
                try makeIdentity(providerVersion: .unavailable),
                try makeIdentity(model: "other"),
                try makeIdentity(modelRevision: .available("other")),
                try makeIdentity(modelRevision: .unavailable),
                try makeIdentity(dimensions: 3),
                try makeIdentity(metric: .l2),
                try makeIdentity(projectionRevision: "other"),
                try makeIdentity(
                    sourceSnapshotDigest: makeSourceSnapshotDigest(
                        value: String(repeating: "c", count: 64)
                    )
                ),
            ]

            for expected in incompatible {
                await #expect(
                    throws: LocalCandidateIndexError.incompatibleIndex(
                        expected: expected,
                        actual: baseline
                    )
                ) {
                    _ = try await SQVectorExactCandidateIndex.open(
                        at: url,
                        identity: expected
                    )
                }
            }
        }

        @Test("persists explicitly unavailable provider version identity")
        func unavailableVersionIdentity() async throws {
            let url = temporaryIndexURL()
            defer { removeIndexFiles(at: url) }
            let identity = try makeIdentity(
                providerVersion: .unavailable,
                modelRevision: .unavailable
            )
            let initial = try await SQVectorExactCandidateIndex.open(at: url, identity: identity)
            try await initial.close()

            let reopened = try await SQVectorExactCandidateIndex.open(at: url, identity: identity)
            #expect(reopened.identity.providerVersion == .unavailable)
            #expect(reopened.identity.modelRevision == .unavailable)
            #expect(reopened.identity.sqVectorPackage == .pinned)
            try await reopened.close()
        }

        @Test("rejects empty available version identities")
        func versionIdentityValidation() {
            #expect(throws: LocalCandidateIndexError.emptyIdentityField(.providerVersion)) {
                _ = try makeIdentity(providerVersion: .available(" "))
            }
            #expect(throws: LocalCandidateIndexError.emptyIdentityField(.modelRevision)) {
                _ = try makeIdentity(modelRevision: .available(""))
            }
            #expect(
                throws: LocalCandidateIndexError.invalidSourceSnapshotDigest("not-a-digest")
            ) {
                _ = try makeSourceSnapshotDigest(value: "not-a-digest")
            }
        }

        @Test("rejects schema v1 storage instead of inferring missing provenance")
        func rejectsSchemaV1Storage() async throws {
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
                        projection_revision TEXT NOT NULL
                    )
                    """
            )
            try await storage.execute(
                sql: """
                    CREATE TABLE swiftdebt_candidates (
                        id TEXT PRIMARY KEY NOT NULL,
                        embedding BLOB NOT NULL,
                        metadata_json BLOB NOT NULL
                    )
                    """
            )
            try await storage.execute(
                sql: """
                    CREATE TABLE swiftdebt_candidate_metadata (
                        candidate_id TEXT NOT NULL
                            REFERENCES swiftdebt_candidates(id) ON DELETE CASCADE,
                        key TEXT NOT NULL,
                        value TEXT NOT NULL,
                        PRIMARY KEY (candidate_id, key)
                    )
                    """
            )
            try await storage.execute(
                sql: """
                    INSERT INTO swiftdebt_index_manifest (
                        singleton, schema_version, namespace, provider,
                        provider_version_state, provider_version_value,
                        model, model_revision_state, model_revision_value,
                        dimensions, metric, projection_revision
                    ) VALUES (1, 1, 'snapshot', 'provider', 'available', 'v1',
                        'model', 'available', 'r1', 2, 'cosine', 'projection-v1')
                    """
            )
            try await storage.close()

            await #expect(throws: LocalCandidateIndexError.unsupportedSchemaVersion(1)) {
                _ = try await SQVectorExactCandidateIndex.open(
                    at: url,
                    identity: makeIdentity()
                )
            }

            let unchanged = try await SQLiteDatabase.open(at: url.path)
            let columns = try await unchanged.fetchRows(
                sql: "PRAGMA table_info(swiftdebt_index_manifest)"
            )
            #expect(
                columns.compactMap { $0["name"]?.stringValue }
                    == [
                        "singleton",
                        "schema_version",
                        "namespace",
                        "provider",
                        "provider_version_state",
                        "provider_version_value",
                        "model",
                        "model_revision_state",
                        "model_revision_value",
                        "dimensions",
                        "metric",
                        "projection_revision",
                    ]
            )
            try await unchanged.close()
        }

        @Test("rejects invalid vector values before storage or search")
        func vectorValidation() async throws {
            let index = try await SQVectorExactCandidateIndex.openInMemory(
                identity: makeIdentity()
            )

            await #expect(
                throws: LocalCandidateIndexError.dimensionMismatch(expected: 2, actual: 1)
            ) {
                try await index.replace(.init(id: "short", vector: [1]))
            }
            await #expect(
                throws: LocalCandidateIndexError.nonFiniteVectorValue(index: 1)
            ) {
                try await index.replace(.init(id: "nan", vector: [1, .nan]))
            }
            await #expect(
                throws: LocalCandidateIndexError.nonFiniteVectorValue(index: 0)
            ) {
                _ = try await index.nearest(to: [.infinity, 1], limit: 1)
            }
            await #expect(throws: LocalCandidateIndexError.zeroNormCosineVector) {
                try await index.replace(.init(id: "zero", vector: [0, 0]))
            }
            await #expect(throws: LocalCandidateIndexError.zeroNormCosineVector) {
                _ = try await index.nearest(to: [0, 0], limit: 1)
            }
            try await index.close()
        }

        @Test("returns incomplete for invalid vectors already present in storage")
        func storedVectorValidation() async throws {
            let invalidVectors: [(label: String, values: [Float])] = [
                ("dimension", [1, 0, 0]),
                ("non-finite", [1, .nan]),
                ("zero-norm", [0, 0]),
            ]

            for invalidVector in invalidVectors {
                let url = temporaryIndexURL()
                defer { removeIndexFiles(at: url) }
                let identity = try makeIdentity()
                let candidateID = "invalid-\(invalidVector.label)"
                let index = try await SQVectorExactCandidateIndex.open(
                    at: url,
                    identity: identity
                )
                try await index.replace(.init(id: candidateID, vector: [1, 0]))
                try await index.close()

                let storage = try await SQLiteDatabase.open(at: url.path)
                let storedVector = try Vector(float32: invalidVector.values)
                try await storage.execute(
                    sql: "UPDATE swiftdebt_candidates SET embedding = ? WHERE id = ?",
                    arguments: [
                        .blob(storedVector.toSqliteVecBlob()),
                        .text(candidateID),
                    ]
                )
                try await storage.close()

                let reopened = try await SQVectorExactCandidateIndex.open(
                    at: url,
                    identity: identity
                )
                let result = try await reopened.nearest(to: [1, 0], limit: 1)
                #expect(
                    result == .incomplete(.corruptStoredCandidate(id: candidateID)),
                    "Expected \(invalidVector.label) vector to be rejected"
                )
                try await reopened.close()
            }
        }

        @Test("allows zero vectors for L2 and bounds result count")
        func l2AndLimits() async throws {
            let index = try await SQVectorExactCandidateIndex.openInMemory(
                identity: makeIdentity(metric: .l2)
            )
            try await index.replace(.init(id: "zero", vector: [0, 0]))
            let result = try await index.nearest(to: [0, 0], limit: 1)
            guard case .complete(let matches) = result else {
                Issue.record("Expected L2 zero-vector search to complete")
                return
            }
            #expect(matches.first?.distance == 0)

            await #expect(
                throws: LocalCandidateIndexError.invalidLimit(requested: 0, maximum: 256)
            ) {
                _ = try await index.nearest(to: [0, 0], limit: 0)
            }
            await #expect(
                throws: LocalCandidateIndexError.invalidLimit(requested: 257, maximum: 256)
            ) {
                _ = try await index.nearest(to: [0, 0], limit: 257)
            }
            try await index.close()
        }

        @Test("rejects empty identifiers and metadata keys")
        func recordIdentity() async throws {
            let index = try await SQVectorExactCandidateIndex.openInMemory(
                identity: makeIdentity()
            )
            await #expect(throws: LocalCandidateIndexError.emptyCandidateID) {
                try await index.replace(.init(id: " ", vector: [1, 0]))
            }
            await #expect(throws: LocalCandidateIndexError.emptyMetadataKey) {
                try await index.replace(
                    .init(id: "valid", vector: [1, 0], metadata: [" ": "value"])
                )
            }
            try await index.close()
        }
    }
#endif
