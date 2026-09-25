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
    projectionRevision: String = "projection-v1"
) throws -> LocalCandidateIndexIdentity {
    try LocalCandidateIndexIdentity(
        namespace: namespace,
        provider: provider,
        providerVersion: providerVersion,
        model: model,
        modelRevision: modelRevision,
        dimensions: dimensions,
        metric: metric,
        projectionRevision: projectionRevision
    )
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
