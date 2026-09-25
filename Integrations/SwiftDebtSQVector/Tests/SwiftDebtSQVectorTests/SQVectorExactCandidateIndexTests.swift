#if canImport(SQVector)
    import Foundation
    import SQVector
    import SwiftDebtSQVector
    import Testing

    @Suite("SQVector exact candidate index")
    struct SQVectorExactCandidateIndexTests {
        @Test("persists replacement, deletion, filters, and deterministic top-k")
        func persistedWorkflow() async throws {
            let url = temporaryIndexURL()
            defer { removeIndexFiles(at: url) }
            let identity = try makeIdentity()
            let index = try await SQVectorExactCandidateIndex.open(at: url, identity: identity)

            try await index.replace(
                .init(
                    id: "a",
                    vector: [1, 0],
                    metadata: [
                        "kind": "function",
                        "module": "A",
                        "obsolete": "yes",
                    ]
                )
            )
            try await index.replace(
                .init(
                    id: "b",
                    vector: [1, 0],
                    metadata: ["kind": "function", "module": "A"]
                )
            )
            try await index.replace(
                .init(
                    id: "c",
                    vector: [0, 1],
                    metadata: ["kind": "type", "module": "A"]
                )
            )
            try await index.replace(
                .init(
                    id: "d",
                    vector: [1, 0],
                    metadata: ["kind": "function", "module": "B"]
                )
            )

            let filter = LocalCandidateFilter(
                metadata: ["module": "A", "kind": "function"]
            )
            let tied = try await index.nearest(to: [1, 0], limit: 2, filter: filter)
            guard case .complete(let tiedMatches) = tied else {
                Issue.record("Expected a complete exact search")
                return
            }
            #expect(tiedMatches.map(\.id) == ["a", "b"])
            #expect(
                tiedMatches.map(\.metadata) == [
                    ["kind": "function", "module": "A", "obsolete": "yes"],
                    ["kind": "function", "module": "A"],
                ])

            try await index.replace(
                .init(
                    id: "a",
                    vector: [0, 1],
                    metadata: ["kind": "function", "module": "A"]
                )
            )
            let replaced = try await index.nearest(to: [1, 0], limit: 2, filter: filter)
            guard case .complete(let replacedMatches) = replaced else {
                Issue.record("Expected a complete exact search after replacement")
                return
            }
            #expect(replacedMatches.map(\.id) == ["b", "a"])
            let removedMetadata = try await index.nearest(
                to: [1, 0],
                limit: 1,
                filter: .init(metadata: ["obsolete": "yes"])
            )
            #expect(removedMetadata == .complete([]))

            #expect(try await index.delete(id: "b"))
            #expect(try await index.delete(id: "b") == false)
            try await index.close()

            let storage = try await SQLiteDatabase.open(at: url.path)
            let deletedMetadataCount = try await storage.fetchCount(
                sql: """
                    SELECT COUNT(*)
                    FROM swiftdebt_candidate_metadata
                    WHERE candidate_id = ?
                    """,
                arguments: [.text("b")]
            )
            #expect(deletedMetadataCount == 0)
            try await storage.close()

            let reopened = try await SQVectorExactCandidateIndex.open(at: url, identity: identity)
            let persisted = try await reopened.nearest(to: [1, 0], limit: 2, filter: filter)
            guard case .complete(let persistedMatches) = persisted else {
                Issue.record("Expected a complete exact search after reopening")
                return
            }
            #expect(persistedMatches.map(\.id) == ["a"])
            #expect(persistedMatches.first?.distance == 1)

            let deletedFilter = LocalCandidateFilter(metadata: ["module": "A"])
            let allModuleA = try await reopened.nearest(
                to: [1, 0],
                limit: 3,
                filter: deletedFilter
            )
            guard case .complete(let moduleAMatches) = allModuleA else {
                Issue.record("Expected filtered retrieval to complete after delete and reopen")
                return
            }
            #expect(moduleAMatches.map(\.id) == ["a", "c"])
            #expect(moduleAMatches.contains(where: { $0.id == "b" }) == false)
            try await reopened.close()
        }

        @Test("returns incomplete instead of truncating an over-budget exact scan")
        func workBudget() async throws {
            let identity = try makeIdentity()
            let budget = try LocalCandidateIndexWorkBudget(maximumCandidates: 2)
            let index = try await SQVectorExactCandidateIndex.openInMemory(
                identity: identity,
                workBudget: budget
            )

            for candidate in [
                LocalCandidate(id: "a", vector: [1, 0], metadata: ["group": "small"]),
                LocalCandidate(id: "b", vector: [0.9, 0.1], metadata: ["group": "small"]),
                LocalCandidate(id: "c", vector: [0, 1], metadata: ["group": "large"]),
            ] {
                try await index.replace(candidate)
            }

            let overBudget = try await index.nearest(to: [1, 0], limit: 2)
            #expect(
                overBudget == .incomplete(.workBudgetExceeded(maximumCandidates: 2))
            )

            let filtered = try await index.nearest(
                to: [1, 0],
                limit: 2,
                filter: .init(metadata: ["group": "small"])
            )
            guard case .complete(let matches) = filtered else {
                Issue.record("Expected filtering to stay within the exact-search budget")
                return
            }
            #expect(matches.map(\.id) == ["a", "b"])
            try await index.close()
        }
    }
#endif
