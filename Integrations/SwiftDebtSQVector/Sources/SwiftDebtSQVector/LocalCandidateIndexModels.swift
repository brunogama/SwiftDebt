public struct LocalCandidate: Equatable, Sendable {
    public let id: String
    public let vector: [Float]
    public let metadata: [String: String]

    public init(id: String, vector: [Float], metadata: [String: String] = [:]) {
        self.id = id
        self.vector = vector
        self.metadata = metadata
    }
}

public struct LocalCandidateFilter: Equatable, Sendable {
    public let metadata: [String: String]

    public init(metadata: [String: String] = [:]) {
        self.metadata = metadata
    }
}

public struct LocalCandidateMatch: Equatable, Sendable {
    public let id: String
    public let distance: Float
    public let metadata: [String: String]

    public init(id: String, distance: Float, metadata: [String: String]) {
        self.id = id
        self.distance = distance
        self.metadata = metadata
    }
}

public enum LocalCandidateIndexUnavailableReason: Equatable, Sendable {
    case unsupportedPlatform
    case staticProductUnavailable
}

public enum LocalCandidateIndexAvailability: Equatable, Sendable {
    case available
    case unavailable(LocalCandidateIndexUnavailableReason)
}

public enum LocalCandidateIndexIncompleteReason: Equatable, Sendable {
    case workBudgetExceeded(maximumCandidates: Int)
    case corruptStoredCandidate(id: String)
    case distanceComputationFailed(id: String)
}

public enum LocalCandidateSearchOutcome: Equatable, Sendable {
    case complete([LocalCandidateMatch])
    case incomplete(LocalCandidateIndexIncompleteReason)
    case unavailable(LocalCandidateIndexUnavailableReason)
}

public enum LocalCandidateIndexError: Error, Equatable, Sendable {
    case emptyIdentityField(LocalCandidateIndexIdentityField)
    case invalidDimensions(Int)
    case unsupportedSchemaVersion(Int)
    case invalidWorkBudget(Int)
    case invalidLimit(requested: Int, maximum: Int)
    case emptyCandidateID
    case emptyMetadataKey
    case dimensionMismatch(expected: Int, actual: Int)
    case nonFiniteVectorValue(index: Int)
    case zeroNormCosineVector
    case incompatibleIndex(
        expected: LocalCandidateIndexIdentity,
        actual: LocalCandidateIndexIdentity
    )
    case corruptStorage
    case unavailable(LocalCandidateIndexUnavailableReason)
    case storageFailure(String)
}

public protocol LocalCandidateIndex: Sendable {
    var identity: LocalCandidateIndexIdentity { get }
    var availability: LocalCandidateIndexAvailability { get }

    func replace(_ candidate: LocalCandidate) async throws
    func delete(id: String) async throws -> Bool
    func nearest(
        to vector: [Float],
        limit: Int,
        filter: LocalCandidateFilter
    ) async throws -> LocalCandidateSearchOutcome
    func close() async throws
}
