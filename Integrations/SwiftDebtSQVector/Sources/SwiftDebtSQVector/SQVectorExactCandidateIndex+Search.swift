#if canImport(SQVector)
    import Foundation
    import SQVector

    extension SQVectorExactCandidateIndex {
        public func nearest(
            to values: [Float],
            limit: Int,
            filter: LocalCandidateFilter = .init()
        ) async throws -> LocalCandidateSearchOutcome {
            do {
                try validateSearch(values: values, limit: limit, filter: filter)
                let rows = try await fetchCandidateRows(filter: filter)
                guard rows.count <= workBudget.maximumCandidates else {
                    return .incomplete(
                        .workBudgetExceeded(maximumCandidates: workBudget.maximumCandidates)
                    )
                }
                return try rank(rows: rows, near: values, limit: limit)
            } catch {
                throw Self.storageError(error)
            }
        }

        private func validateSearch(
            values: [Float],
            limit: Int,
            filter: LocalCandidateFilter
        ) throws {
            try identity.validateVector(values)
            guard (1...Self.maximumResults).contains(limit) else {
                throw LocalCandidateIndexError.invalidLimit(
                    requested: limit,
                    maximum: Self.maximumResults
                )
            }
            for key in filter.metadata.keys
            where key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw LocalCandidateIndexError.emptyMetadataKey
            }
        }

        private func fetchCandidateRows(
            filter: LocalCandidateFilter
        ) async throws -> [SQLiteRow] {
            let filters = filter.metadata.sorted { utf8Precedes($0.key, $1.key) }
            let clauses = filters.indices.map { index in
                """
                EXISTS (
                    SELECT 1
                    FROM swiftdebt_candidate_metadata AS m\(index)
                    WHERE m\(index).candidate_id = c.id
                        AND m\(index).key = ?
                        AND m\(index).value = ?
                )
                """
            }
            let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            var arguments = filters.flatMap {
                [$0.key.storageValue, $0.value.storageValue]
            }
            arguments.append(Int64(workBudget.maximumCandidates + 1).storageValue)

            return try await connection.fetchRows(
                sql: """
                    SELECT c.id, c.embedding, c.metadata_json
                    FROM swiftdebt_candidates AS c
                    \(whereClause)
                    ORDER BY c.id COLLATE BINARY ASC
                    LIMIT ?
                    """,
                arguments: arguments
            )
        }

        private func rank(
            rows: [SQLiteRow],
            near values: [Float],
            limit: Int
        ) throws -> LocalCandidateSearchOutcome {
            let query = try Vector(float32: values)
            var matches = [LocalCandidateMatch]()
            matches.reserveCapacity(rows.count)

            for row in rows {
                guard
                    let id = row["id"]?.stringValue,
                    let embedding = row["embedding"]?.blobValue,
                    let metadataJSON = row["metadata_json"]?.blobValue,
                    let vector = try? Vector.fromSqliteVecBlob(embedding),
                    let storedValues = vector.float32Array,
                    let metadata = try? JSONDecoder().decode(
                        [String: String].self,
                        from: metadataJSON
                    )
                else {
                    return .incomplete(.corruptStoredCandidate(id: rowID(row)))
                }

                do {
                    try identity.validateVector(storedValues)
                    let distance = try VectorDistanceComputation.computeDistance(
                        from: query,
                        to: vector,
                        metric: identity.metric.sqVectorMetric
                    )
                    guard distance.isFinite else {
                        return .incomplete(.distanceComputationFailed(id: id))
                    }
                    matches.append(
                        LocalCandidateMatch(id: id, distance: distance, metadata: metadata)
                    )
                } catch let error as LocalCandidateIndexError {
                    switch error {
                    case .dimensionMismatch, .nonFiniteVectorValue, .zeroNormCosineVector:
                        return .incomplete(.corruptStoredCandidate(id: id))
                    default:
                        throw error
                    }
                } catch {
                    return .incomplete(.distanceComputationFailed(id: id))
                }
            }

            matches.sort {
                if $0.distance != $1.distance {
                    return $0.distance < $1.distance
                }
                return utf8Precedes($0.id, $1.id)
            }
            return .complete(Array(matches.prefix(limit)))
        }

        private func rowID(_ row: SQLiteRow) -> String {
            row["id"]?.stringValue ?? "<unreadable>"
        }
    }

    extension LocalCandidateDistanceMetric {
        fileprivate var sqVectorMetric: DistanceMetric {
            switch self {
            case .cosine:
                .cosine
            case .l2:
                .l2
            }
        }
    }
#endif
