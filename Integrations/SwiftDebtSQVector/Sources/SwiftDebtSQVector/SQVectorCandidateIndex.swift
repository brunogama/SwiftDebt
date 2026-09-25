import SQVector
import SwiftDebtKit

/// Local vector candidate retrieval for SwiftDebt.
/// Distances identify candidates only; they do not establish a debt detection.
public actor SQVectorCandidateIndex {
    public struct Candidate: Sendable, Equatable {
        public let rowID: Int64
        public let distance: Float
    }

    public enum IndexError: Error, Equatable {
        case invalidDimensions
        case invalidLimit
        case dimensionMismatch(expected: Int, actual: Int)
    }

    private let connection: SQLiteConnection
    public let dimensions: Int

    private init(connection: SQLiteConnection, dimensions: Int) {
        self.connection = connection
        self.dimensions = dimensions
    }

    public static func openInMemory(dimensions: Int) async throws -> SQVectorCandidateIndex {
        guard dimensions > 0 else { throw IndexError.invalidDimensions }
        let connection = try await SQLiteDatabase.openInMemory()
        let definition = try Vec0TableDefinition(
            tableName: "swiftdebt_candidates",
            vectorColumn: "embedding",
            dimensions: dimensions,
            elementType: .float32
        )
        try await connection.createVec0Table(definition)
        return SQVectorCandidateIndex(connection: connection, dimensions: dimensions)
    }

    public func insert(rowID: Int64, embedding: [Float]) async throws {
        let vector = try checkedVector(embedding)
        try await connection.insertVec0(
            tableName: "swiftdebt_candidates",
            rowId: rowID,
            vectorColumn: "embedding",
            vector: vector
        )
    }

    public func nearest(to embedding: [Float], limit: Int) async throws -> [Candidate] {
        guard limit > 0 else { throw IndexError.invalidLimit }
        let vector = try checkedVector(embedding)
        let matches = try await connection.queryVec0KNN(
            tableName: "swiftdebt_candidates",
            vectorColumn: "embedding",
            query: vector,
            limit: limit
        )
        return matches.map { Candidate(rowID: $0.rowId, distance: $0.distance) }
    }

    public func delete(rowID: Int64) async throws {
        try await connection.execute(
            sql: "DELETE FROM swiftdebt_candidates WHERE rowid = ?",
            arguments: [.integer(rowID)]
        )
    }

    private func checkedVector(_ values: [Float]) throws -> Vector {
        guard values.count == dimensions else {
            throw IndexError.dimensionMismatch(expected: dimensions, actual: values.count)
        }
        return try Vector(float32: values)
    }
}
