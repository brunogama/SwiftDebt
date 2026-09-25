import SwiftDebtSQVector
import Testing

@Suite("SQVector candidate index")
struct SQVectorCandidateIndexTests {
    @Test func insertsQueriesAndDeletesCandidates() async throws {
        let index = try await SQVectorCandidateIndex.openInMemory(dimensions: 2)
        try await index.insert(rowID: 10, embedding: [0, 0])
        try await index.insert(rowID: 20, embedding: [1, 1])

        let matches = try await index.nearest(to: [0, 0], limit: 2)
        #expect(matches.map(\.rowID) == [10, 20])
        let first = try #require(matches.first)
        #expect(first.distance == 0)

        try await index.delete(rowID: 10)
        let remaining = try await index.nearest(to: [0, 0], limit: 2)
        #expect(remaining.map(\.rowID) == [20])
    }

    @Test func rejectsWrongDimensionsBeforeQuery() async throws {
        let index = try await SQVectorCandidateIndex.openInMemory(dimensions: 2)
        await #expect(throws: SQVectorCandidateIndex.IndexError.dimensionMismatch(expected: 2, actual: 1)) {
            try await index.insert(rowID: 1, embedding: [1])
        }
    }
}
