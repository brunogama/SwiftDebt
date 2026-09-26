import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 effective-configuration persistence")
struct EffectiveConfigurationPersistenceTests {
    @Test("Persisted configuration authority is required during decode")
    func missingConfigurationDeclarationFailsClosed() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture, maximumFileBytes: 4_096).status == 0)
        _ = try fixture.commit(source: Self.resolvedSource, message: "remove forced try")
        #expect(try analyze(fixture, maximumFileBytes: 8_192).status == 0)

        var root = try artifactJSONObject(at: fixture.artifact)
        var findings = try #require(root["findings"] as? [[String: Any]])
        var finding = try #require(findings.first)
        var events = try #require(finding["events"] as? [[String: Any]])
        var resolution = try #require(events.last)
        var comparisons = try #require(resolution["semanticComparisons"] as? [[String: Any]])
        var comparison = try #require(comparisons.first)
        comparison.removeValue(forKey: "configurationCompatibilityDeclaration")
        comparisons[0] = comparison
        resolution["semanticComparisons"] = comparisons
        events[events.count - 1] = resolution
        finding["events"] = events
        findings[0] = finding
        root["findings"] = findings

        let corrupted = try lifecycleJSONData(root)
        try corrupted.write(to: fixture.artifact, options: .atomic)
        let store = LifecycleArtifactStore(artifactURL: fixture.artifact)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fixture.artifact) == corrupted)
    }

    @Test("Persisted effective-configuration dimensions are bound to their fingerprint")
    func tamperedEffectiveConfigurationFailsClosed() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture, maximumFileBytes: 4_096).status == 0)

        var root = try artifactJSONObject(at: fixture.artifact)
        var snapshots = try #require(root["snapshots"] as? [[String: Any]])
        var snapshot = try #require(snapshots.first)
        var provenance = try #require(snapshot["provenance"] as? [String: Any])
        var configuration = try #require(
            provenance["effectiveConfiguration"] as? [String: Any]
        )
        configuration["maximumFileBytes"] = 8_192
        provenance["effectiveConfiguration"] = configuration
        snapshot["provenance"] = provenance
        snapshots[0] = snapshot
        root["snapshots"] = snapshots

        let corrupted = try lifecycleJSONData(root)
        try corrupted.write(to: fixture.artifact, options: .atomic)
        let store = LifecycleArtifactStore(artifactURL: fixture.artifact)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fixture.artifact) == corrupted)
    }

    private func analyze(
        _ fixture: TemporaryLifecycleGitRepository,
        maximumFileBytes: Int
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
            "--max-file-bytes", String(maximumFileBytes),
            "--jobs", "2",
        ])
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }

        """

    private static let resolvedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try? load() }

        """
}
