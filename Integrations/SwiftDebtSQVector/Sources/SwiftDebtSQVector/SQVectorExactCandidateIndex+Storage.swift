#if canImport(SQVector)
    import SQVector

    extension SQVectorExactCandidateIndex {
        static func prepareStorage(
            _ connection: SQLiteConnection,
            identity: LocalCandidateIndexIdentity
        ) async throws {
            do {
                try await connection.executeInTransaction([
                    .init(
                        sql: """
                            CREATE TABLE IF NOT EXISTS swiftdebt_index_manifest (
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
                                sqvector_package_version_state TEXT NOT NULL,
                                sqvector_package_version_value TEXT,
                                sqvector_package_revision TEXT NOT NULL
                            )
                            """),
                    .init(
                        sql: """
                            CREATE TABLE IF NOT EXISTS swiftdebt_candidates (
                                id TEXT PRIMARY KEY NOT NULL,
                                embedding BLOB NOT NULL,
                                metadata_json BLOB NOT NULL
                            )
                            """),
                    .init(
                        sql: """
                            CREATE TABLE IF NOT EXISTS swiftdebt_candidate_metadata (
                                candidate_id TEXT NOT NULL
                                    REFERENCES swiftdebt_candidates(id) ON DELETE CASCADE,
                                key TEXT NOT NULL,
                                value TEXT NOT NULL,
                                PRIMARY KEY (candidate_id, key)
                            )
                            """),
                    .init(
                        sql: """
                            CREATE INDEX IF NOT EXISTS swiftdebt_candidate_metadata_lookup
                            ON swiftdebt_candidate_metadata(key, value, candidate_id)
                            """),
                ])

                guard
                    let row = try await connection.fetchRow(
                        sql: "SELECT * FROM swiftdebt_index_manifest WHERE singleton = 1"
                    )
                else {
                    let candidateCount = try await connection.fetchCount(
                        sql: "SELECT COUNT(*) FROM swiftdebt_candidates"
                    )
                    let metadataCount = try await connection.fetchCount(
                        sql: "SELECT COUNT(*) FROM swiftdebt_candidate_metadata"
                    )
                    guard candidateCount == 0, metadataCount == 0 else {
                        throw LocalCandidateIndexError.corruptStorage
                    }
                    try await insertManifest(connection, identity: identity)
                    return
                }

                let actual = try decodeIdentity(from: row)
                guard actual == identity else {
                    throw LocalCandidateIndexError.incompatibleIndex(
                        expected: identity,
                        actual: actual
                    )
                }
            } catch {
                throw storageError(error)
            }
        }

        private static func insertManifest(
            _ connection: SQLiteConnection,
            identity: LocalCandidateIndexIdentity
        ) async throws {
            try await connection.execute(
                sql: """
                    INSERT INTO swiftdebt_index_manifest (
                        singleton,
                        schema_version,
                        namespace,
                        provider,
                        provider_version_state,
                        provider_version_value,
                        model,
                        model_revision_state,
                        model_revision_value,
                        dimensions,
                        metric,
                        projection_revision,
                        source_snapshot_digest_algorithm,
                        source_snapshot_digest_value,
                        sqvector_package_version_state,
                        sqvector_package_version_value,
                        sqvector_package_revision
                    ) VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    .integer(Int64(identity.schemaVersion)),
                    .text(identity.namespace),
                    .text(identity.provider),
                    .text(identity.providerVersion.storageState),
                    identity.providerVersion.storageValue.map { .text($0) } ?? .null,
                    .text(identity.model),
                    .text(identity.modelRevision.storageState),
                    identity.modelRevision.storageValue.map { .text($0) } ?? .null,
                    .integer(Int64(identity.dimensions)),
                    .text(identity.metric.rawValue),
                    .text(identity.projectionRevision),
                    .text(identity.sourceSnapshotDigest.algorithm.rawValue),
                    .text(identity.sourceSnapshotDigest.value),
                    .text(identity.sqVectorPackage.version.storageState),
                    identity.sqVectorPackage.version.storageValue.map { .text($0) } ?? .null,
                    .text(identity.sqVectorPackage.revision),
                ]
            )
        }

        private static func decodeIdentity(from row: SQLiteRow) throws -> LocalCandidateIndexIdentity {
            guard
                let schemaVersion = row["schema_version"]?.intValue,
                let schemaVersionInt = Int(exactly: schemaVersion)
            else {
                throw LocalCandidateIndexError.corruptStorage
            }
            guard schemaVersionInt == LocalCandidateIndexIdentity.currentSchemaVersion else {
                throw LocalCandidateIndexError.unsupportedSchemaVersion(schemaVersionInt)
            }
            guard
                let namespace = row["namespace"]?.stringValue,
                let provider = row["provider"]?.stringValue,
                let providerVersionState = row["provider_version_state"]?.stringValue,
                let model = row["model"]?.stringValue,
                let modelRevisionState = row["model_revision_state"]?.stringValue,
                let dimensions = row["dimensions"]?.intValue,
                let metricValue = row["metric"]?.stringValue,
                let metric = LocalCandidateDistanceMetric(rawValue: metricValue),
                let projectionRevision = row["projection_revision"]?.stringValue,
                let dimensionsInt = Int(exactly: dimensions),
                let digestAlgorithmValue = row["source_snapshot_digest_algorithm"]?.stringValue,
                let digestAlgorithm = LocalCandidateDigestAlgorithm(
                    rawValue: digestAlgorithmValue
                ),
                let digestValue = row["source_snapshot_digest_value"]?.stringValue,
                let sqVectorPackageVersionState = row[
                    "sqvector_package_version_state"
                ]?.stringValue,
                let sqVectorPackageRevision = row["sqvector_package_revision"]?.stringValue
            else {
                throw LocalCandidateIndexError.corruptStorage
            }
            let providerVersion = try versionIdentity(
                state: providerVersionState,
                value: row["provider_version_value"]?.stringValue
            )
            let modelRevision = try versionIdentity(
                state: modelRevisionState,
                value: row["model_revision_value"]?.stringValue
            )
            let sourceSnapshotDigest = try LocalCandidateSourceSnapshotDigest(
                algorithm: digestAlgorithm,
                value: digestValue
            )
            let sqVectorPackageVersion = try versionIdentity(
                state: sqVectorPackageVersionState,
                value: row["sqvector_package_version_value"]?.stringValue
            )
            let sqVectorPackage = try SQVectorPackageIdentity(
                version: sqVectorPackageVersion,
                revision: sqVectorPackageRevision
            )

            return LocalCandidateIndexIdentity(
                schemaVersion: schemaVersionInt,
                namespace: namespace,
                provider: provider,
                providerVersion: providerVersion,
                model: model,
                modelRevision: modelRevision,
                dimensions: dimensionsInt,
                metric: metric,
                projectionRevision: projectionRevision,
                sourceSnapshotDigest: sourceSnapshotDigest,
                sqVectorPackage: sqVectorPackage
            )
        }

        private static func versionIdentity(
            state: String,
            value: String?
        ) throws -> LocalCandidateVersionIdentity {
            switch (state, value) {
            case ("available", .some(let value)):
                .available(value)
            case ("unavailable", .none):
                .unavailable
            default:
                throw LocalCandidateIndexError.corruptStorage
            }
        }
    }

    extension LocalCandidateVersionIdentity {
        fileprivate var storageState: String {
            switch self {
            case .available:
                "available"
            case .unavailable:
                "unavailable"
            }
        }

        fileprivate var storageValue: String? {
            if case .available(let value) = self {
                value
            } else {
                nil
            }
        }
    }
#endif
