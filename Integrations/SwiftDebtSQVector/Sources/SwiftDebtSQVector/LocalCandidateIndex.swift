import Foundation

public enum LocalCandidateDistanceMetric: String, Codable, CaseIterable, Sendable {
    case cosine
    case l2
}

public enum LocalCandidateIndexIdentityField: String, Codable, Sendable {
    case namespace
    case provider
    case providerVersion
    case model
    case modelRevision
    case projectionRevision
    case sqVectorPackageVersion
    case sqVectorPackageRevision
}

public enum LocalCandidateVersionIdentity: Codable, Equatable, Sendable {
    case available(String)
    case unavailable

    func validate(field: LocalCandidateIndexIdentityField) throws {
        if case .available(let value) = self,
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw LocalCandidateIndexError.emptyIdentityField(field)
        }
    }
}

public struct LocalCandidateIndexIdentity: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let namespace: String
    public let provider: String
    public let providerVersion: LocalCandidateVersionIdentity
    public let model: String
    public let modelRevision: LocalCandidateVersionIdentity
    public let dimensions: Int
    public let metric: LocalCandidateDistanceMetric
    public let projectionRevision: String
    public let sourceSnapshotDigest: LocalCandidateSourceSnapshotDigest
    public let sqVectorPackage: SQVectorPackageIdentity

    public init(
        namespace: String,
        provider: String,
        providerVersion: LocalCandidateVersionIdentity,
        model: String,
        modelRevision: LocalCandidateVersionIdentity,
        dimensions: Int,
        metric: LocalCandidateDistanceMetric,
        projectionRevision: String,
        sourceSnapshotDigest: LocalCandidateSourceSnapshotDigest,
        sqVectorPackage: SQVectorPackageIdentity
    ) throws {
        self.init(
            schemaVersion: Self.currentSchemaVersion,
            namespace: namespace,
            provider: provider,
            providerVersion: providerVersion,
            model: model,
            modelRevision: modelRevision,
            dimensions: dimensions,
            metric: metric,
            projectionRevision: projectionRevision,
            sourceSnapshotDigest: sourceSnapshotDigest,
            sqVectorPackage: sqVectorPackage
        )
        try validate()
    }

    init(
        schemaVersion: Int,
        namespace: String,
        provider: String,
        providerVersion: LocalCandidateVersionIdentity,
        model: String,
        modelRevision: LocalCandidateVersionIdentity,
        dimensions: Int,
        metric: LocalCandidateDistanceMetric,
        projectionRevision: String,
        sourceSnapshotDigest: LocalCandidateSourceSnapshotDigest,
        sqVectorPackage: SQVectorPackageIdentity
    ) {
        self.schemaVersion = schemaVersion
        self.namespace = namespace
        self.provider = provider
        self.providerVersion = providerVersion
        self.model = model
        self.modelRevision = modelRevision
        self.dimensions = dimensions
        self.metric = metric
        self.projectionRevision = projectionRevision
        self.sourceSnapshotDigest = sourceSnapshotDigest
        self.sqVectorPackage = sqVectorPackage
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LocalCandidateIndexError.unsupportedSchemaVersion(schemaVersion)
        }
        guard dimensions > 0 else {
            throw LocalCandidateIndexError.invalidDimensions(dimensions)
        }

        for (field, value) in [
            (LocalCandidateIndexIdentityField.namespace, namespace),
            (.provider, provider),
            (.model, model),
            (.projectionRevision, projectionRevision),
        ] where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LocalCandidateIndexError.emptyIdentityField(field)
        }
        try providerVersion.validate(field: .providerVersion)
        try modelRevision.validate(field: .modelRevision)
    }

    func validateVector(_ values: [Float]) throws {
        guard values.count == dimensions else {
            throw LocalCandidateIndexError.dimensionMismatch(
                expected: dimensions,
                actual: values.count
            )
        }

        if let index = values.firstIndex(where: { !$0.isFinite }) {
            throw LocalCandidateIndexError.nonFiniteVectorValue(index: index)
        }

        if metric == .cosine {
            let squaredNorm = values.reduce(into: 0.0) { result, value in
                result += Double(value) * Double(value)
            }
            guard squaredNorm > 0 else {
                throw LocalCandidateIndexError.zeroNormCosineVector
            }
        }
    }
}

public struct LocalCandidateIndexWorkBudget: Equatable, Sendable {
    public static let standard = Self(validatedMaximumCandidates: 10_000)

    public let maximumCandidates: Int

    public init(maximumCandidates: Int) throws {
        guard maximumCandidates > 0, maximumCandidates < Int.max else {
            throw LocalCandidateIndexError.invalidWorkBudget(maximumCandidates)
        }
        self.maximumCandidates = maximumCandidates
    }

    private init(validatedMaximumCandidates: Int) {
        self.maximumCandidates = validatedMaximumCandidates
    }
}
