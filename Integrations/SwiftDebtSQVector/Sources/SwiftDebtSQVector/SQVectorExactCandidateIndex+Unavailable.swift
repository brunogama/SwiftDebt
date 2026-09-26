#if !canImport(SQVector)
    import Foundation

    public actor SQVectorExactCandidateIndex: LocalCandidateIndex {
        public static let maximumResults = 256
        public static let availability = LocalCandidateIndexAvailability.unavailable(
            unavailableReason
        )

        public nonisolated let identity: LocalCandidateIndexIdentity
        public nonisolated let availability = LocalCandidateIndexAvailability.unavailable(
            unavailableReason
        )

        private init(identity: LocalCandidateIndexIdentity) {
            self.identity = identity
        }

        public static func open(
            at _: URL,
            identity: LocalCandidateIndexIdentity,
            workBudget _: LocalCandidateIndexWorkBudget = .standard
        ) async throws -> SQVectorExactCandidateIndex {
            Self(identity: identity)
        }

        public static func openInMemory(
            identity: LocalCandidateIndexIdentity,
            workBudget _: LocalCandidateIndexWorkBudget = .standard
        ) async throws -> SQVectorExactCandidateIndex {
            Self(identity: identity)
        }

        public func replace(_: LocalCandidate) async throws {
            throw LocalCandidateIndexError.unavailable(Self.unavailableReason)
        }

        public func delete(id _: String) async throws -> Bool {
            throw LocalCandidateIndexError.unavailable(Self.unavailableReason)
        }

        public func nearest(
            to _: [Float],
            limit _: Int,
            filter _: LocalCandidateFilter = .init()
        ) async throws -> LocalCandidateSearchOutcome {
            .unavailable(Self.unavailableReason)
        }

        public func close() async throws {}

        private static var unavailableReason: LocalCandidateIndexUnavailableReason {
            #if os(macOS) || os(iOS)
                .staticProductUnavailable
            #else
                .unsupportedPlatform
            #endif
        }
    }
#endif
