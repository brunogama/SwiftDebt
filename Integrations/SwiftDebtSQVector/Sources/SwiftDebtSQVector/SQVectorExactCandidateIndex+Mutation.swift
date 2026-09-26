#if canImport(SQVector)
    import Foundation
    import SQVector

    extension SQVectorExactCandidateIndex {
        public func replace(_ candidate: LocalCandidate) async throws {
            do {
                guard !candidate.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LocalCandidateIndexError.emptyCandidateID
                }
                try identity.validateVector(candidate.vector)
                for key in candidate.metadata.keys
                where key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw LocalCandidateIndexError.emptyMetadataKey
                }

                let vector = try Vector(float32: candidate.vector)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let metadataJSON = try encoder.encode(candidate.metadata)

                var statements: [SQLiteConnection.SQLStatement] = [
                    .init(
                        sql: "DELETE FROM swiftdebt_candidate_metadata WHERE candidate_id = ?",
                        arguments: [.text(candidate.id)]
                    ),
                    .init(
                        sql: """
                            INSERT INTO swiftdebt_candidates (id, embedding, metadata_json)
                            VALUES (?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                embedding = excluded.embedding,
                                metadata_json = excluded.metadata_json
                            """,
                        arguments: [
                            .text(candidate.id),
                            .blob(vector.toSqliteVecBlob()),
                            .blob(metadataJSON),
                        ]
                    ),
                ]
                statements.append(
                    contentsOf: candidate.metadata.sorted(by: metadataOrder).map {
                        .init(
                            sql: """
                                INSERT INTO swiftdebt_candidate_metadata (candidate_id, key, value)
                                VALUES (?, ?, ?)
                                """,
                            arguments: [.text(candidate.id), .text($0.key), .text($0.value)]
                        )
                    })
                try await connection.executeInTransaction(statements)
            } catch {
                throw Self.storageError(error)
            }
        }

        public func delete(id: String) async throws -> Bool {
            do {
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LocalCandidateIndexError.emptyCandidateID
                }
                let existed = try await connection.fetchExists(
                    sql: "SELECT 1 FROM swiftdebt_candidates WHERE id = ?",
                    arguments: [.text(id)]
                )
                try await connection.executeInTransaction([
                    .init(
                        sql: "DELETE FROM swiftdebt_candidate_metadata WHERE candidate_id = ?",
                        arguments: [.text(id)]
                    ),
                    .init(
                        sql: "DELETE FROM swiftdebt_candidates WHERE id = ?",
                        arguments: [.text(id)]
                    ),
                ])
                return existed
            } catch {
                throw Self.storageError(error)
            }
        }

        private func metadataOrder(
            _ lhs: Dictionary<String, String>.Element,
            _ rhs: Dictionary<String, String>.Element
        ) -> Bool {
            utf8Precedes(lhs.key, rhs.key)
        }
    }

    func utf8Precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
#endif
