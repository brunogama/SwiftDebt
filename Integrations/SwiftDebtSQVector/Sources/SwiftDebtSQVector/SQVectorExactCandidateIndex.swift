#if canImport(SQVector)
    import Foundation
    import SQVector

    public actor SQVectorExactCandidateIndex: LocalCandidateIndex {
        public static let maximumResults = 256
        public static let availability = LocalCandidateIndexAvailability.available

        public nonisolated let identity: LocalCandidateIndexIdentity
        public nonisolated let availability = LocalCandidateIndexAvailability.available

        let connection: SQLiteConnection
        let workBudget: LocalCandidateIndexWorkBudget

        private init(
            connection: SQLiteConnection,
            identity: LocalCandidateIndexIdentity,
            workBudget: LocalCandidateIndexWorkBudget
        ) {
            self.connection = connection
            self.identity = identity
            self.workBudget = workBudget
        }

        public static func open(
            at url: URL,
            identity: LocalCandidateIndexIdentity,
            workBudget: LocalCandidateIndexWorkBudget = .standard
        ) async throws -> SQVectorExactCandidateIndex {
            try identity.validate()
            let connection: SQLiteConnection
            do {
                connection = try await SQLiteDatabase.open(at: url.path)
            } catch {
                throw storageError(error)
            }
            return try await finishOpening(
                connection: connection,
                identity: identity,
                workBudget: workBudget
            )
        }

        public static func openInMemory(
            identity: LocalCandidateIndexIdentity,
            workBudget: LocalCandidateIndexWorkBudget = .standard
        ) async throws -> SQVectorExactCandidateIndex {
            try identity.validate()
            let connection: SQLiteConnection
            do {
                connection = try await SQLiteDatabase.openInMemory()
            } catch {
                throw storageError(error)
            }
            return try await finishOpening(
                connection: connection,
                identity: identity,
                workBudget: workBudget
            )
        }

        public func close() async throws {
            do {
                try await connection.close()
            } catch {
                throw Self.storageError(error)
            }
        }

        static func finishOpening(
            connection: SQLiteConnection,
            identity: LocalCandidateIndexIdentity,
            workBudget: LocalCandidateIndexWorkBudget
        ) async throws -> SQVectorExactCandidateIndex {
            do {
                try identity.validate()
                try await prepareStorage(connection, identity: identity)
                return Self(
                    connection: connection,
                    identity: identity,
                    workBudget: workBudget
                )
            } catch {
                try? await connection.close()
                throw storageError(error)
            }
        }

        static func storageError(_ error: any Error) -> LocalCandidateIndexError {
            if let error = error as? LocalCandidateIndexError {
                return error
            }
            return .storageFailure(String(describing: error))
        }
    }
#endif
