import Foundation
import SwiftDebtSQVector

func makeIdentity(
    namespace: String = "repository-snapshot",
    provider: String = "local-provider",
    providerVersion: LocalCandidateVersionIdentity = .available("provider-v1"),
    model: String = "test-model",
    modelRevision: LocalCandidateVersionIdentity = .available("model-r1"),
    dimensions: Int = 2,
    metric: LocalCandidateDistanceMetric = .cosine,
    projectionRevision: String = "projection-v1",
    sourceSnapshotDigest: LocalCandidateSourceSnapshotDigest? = nil,
    sqVectorPackage: SQVectorPackageIdentity? = nil
) throws -> LocalCandidateIndexIdentity {
    try LocalCandidateIndexIdentity(
        namespace: namespace,
        provider: provider,
        providerVersion: providerVersion,
        model: model,
        modelRevision: modelRevision,
        dimensions: dimensions,
        metric: metric,
        projectionRevision: projectionRevision,
        sourceSnapshotDigest: sourceSnapshotDigest ?? makeSourceSnapshotDigest(),
        sqVectorPackage: sqVectorPackage ?? makeSQVectorPackageIdentity()
    )
}

func makeSourceSnapshotDigest(
    value: String = String(repeating: "a", count: 64)
) throws -> LocalCandidateSourceSnapshotDigest {
    try LocalCandidateSourceSnapshotDigest(sha256: value)
}

func makeSQVectorPackageIdentity(
    version: String = "test-version-1",
    revision: String = String(repeating: "b", count: 40)
) throws -> SQVectorPackageIdentity {
    try SQVectorPackageIdentity(version: version, revision: revision)
}

func temporaryIndexURL() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "swiftdebt-index-\(UUID().uuidString).sqlite")
}

func removeIndexFiles(at url: URL) {
    for suffix in ["", "-shm", "-wal"] {
        try? FileManager.default.removeItem(atPath: url.path + suffix)
    }
}
