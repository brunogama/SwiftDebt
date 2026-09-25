import Foundation
import SwiftDebtLifecycle
import Testing

func analyzeScope(repository: URL, artifact: URL) throws -> LifecycleCLIRunResult {
    try runLifecycleCLI([
        "analyze", repository.path,
        "--format", "json",
        "--lifecycle-artifact", artifact.path,
        "--jobs", "2",
    ])
}

func analyzeScope(manifest: URL, artifact: URL) throws -> LifecycleCLIRunResult {
    try runLifecycleCLI([
        "analyze",
        "--manifest", manifest.path,
        "--format", "json",
        "--lifecycle-artifact", artifact.path,
        "--jobs", "2",
    ])
}

func scopeManifestJSON(root: URL, sources: [String]) throws -> String {
    let object: [String: Any] = [
        "root": root.path,
        "sources": sources.map { ["path": $0, "module": "Workspace"] },
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try #require(String(data: data, encoding: .utf8))
}

func latestScopeSnapshot(in artifact: LifecycleArtifact) -> ObservationSnapshot? {
    artifact.snapshots.max {
        $0.provenance.lineage.sequence < $1.provenance.lineage.sequence
    }
}

let scopeDetectedSource = """
    func load() throws -> Int { 1 }
    func run() { _ = try! load() }
    """

let scopeCleanSource = """
    func clean() -> Int { 1 }
    """
