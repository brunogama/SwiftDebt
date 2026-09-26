import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 schema 2 migration CLI acceptance")
struct LegacySchemaTwoCLIWorkflowTests {
    @Test("A real schema 2 resolved Finding remains readable")
    func legacyResolutionRemainsReadable() throws {
        let fixture = try #require(
            Bundle.module.url(forResource: "LegacySchemaTwoResolved", withExtension: "json")
        )
        let original = try Data(contentsOf: fixture)
        let result = try runLifecycleCLI(["lifecycle", "inventory", fixture.path])

        #expect(result.status == 0)
        #expect(result.standardOutput.contains("resolved"))
        #expect(try Data(contentsOf: fixture) == original)
    }

    @Test("Accepted ingestion upgrades schema 2 while preserving its historical claim")
    func acceptedIngestionPreservesLegacyEvidence() throws {
        let source = try #require(
            Bundle.module.url(forResource: "LegacySchemaTwoResolved", withExtension: "json")
        )
        let temporary = try TemporaryLifecycleArtifact()
        try Data(contentsOf: source).write(to: temporary.url, options: .atomic)
        let store = LifecycleArtifactStore(artifactURL: temporary.url)
        let original = try Data(contentsOf: temporary.url)
        let migrated = try store.load()
        let historical = try #require(migrated.findings.first)
        let parentID = try #require(migrated.headSnapshotIDs.first)
        let parent = try #require(migrated.snapshot(id: parentID))
        #expect(migrated.schemaVersion == 3)
        #expect(migrated.legacyProcessedSnapshotIDs.count == 2)
        #expect(historical.events.allSatisfy { $0.evidenceContract == .legacySchemaTwo })
        #expect(historical.events.allSatisfy { $0.semanticComparisons.isEmpty })
        #expect(try Data(contentsOf: temporary.url) == original)

        let successor = try makeObservation(
            id: "post-migration-snapshot",
            lineage: parent.provenance.lineage.lineageID.rawValue,
            sequence: parent.provenance.lineage.sequence + 1,
            predecessor: parent.id.rawValue,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        #expect(try store.ingest(successor).status == .accepted)
        let persisted = try store.load()
        let persistedFinding = try #require(persisted.finding(id: historical.id))
        let newFinding = try #require(
            persisted.findings.first { $0.firstObservationSnapshotID == successor.id }
        )
        #expect(persisted.schemaVersion == 3)
        #expect(persistedFinding.events == historical.events)
        #expect(newFinding.events.first?.evidenceContract == .semanticComparisonV1)
        #expect(persisted.legacyProcessedSnapshotIDs == migrated.legacyProcessedSnapshotIDs)

        var corrupted = try artifactJSONObject(at: temporary.url)
        var findings = try #require(corrupted["findings"] as? [[String: Any]])
        let newFindingIndex = try #require(
            findings.firstIndex { $0["id"] as? String == newFinding.id.rawValue }
        )
        var events = try #require(findings[newFindingIndex]["events"] as? [[String: Any]])
        events[0]["evidenceContract"] = "legacy-schema-2"
        findings[newFindingIndex]["events"] = events
        corrupted["findings"] = findings
        try lifecycleJSONData(corrupted).write(to: temporary.url, options: .atomic)
        let result = try runLifecycleCLI(["lifecycle", "inventory", temporary.url.path])
        #expect(result.status == 2)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("migration boundary"))
    }

    @Test("A genuine schema 2 configuration cannot claim unproved continuity")
    func genuineLegacyConfigurationRemainsUnresolved() throws {
        let source = try #require(
            Bundle.module.url(forResource: "LegacySchemaTwoGitReintroduction", withExtension: "json")
        )
        let fixture = try TemporaryLifecycleGitRepository()
        let artifact = fixture.directory.appendingPathComponent("legacy.json")
        let forcedSource = "func load() throws -> Int { 1 }\nlet value = try! load()\n"
        let handledSource = "func load() throws -> Int { 1 }\nlet value = try? load()\n"
        try datedCommit(fixture, source: forcedSource, message: "add force try", date: "2026-01-01T00:00:00 +0000")
        try datedCommit(fixture, source: handledSource, message: "resolve force try", date: "2026-01-02T00:00:00 +0000")
        #expect(
            try fixture.gitOutput(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
                == "c3e20615787a29eac1a19cc7abae0df4325788eb")
        try FileManager.default.copyItem(at: source, to: artifact)
        try datedCommit(
            fixture, source: forcedSource, message: "reintroduce force try", date: "2026-01-03T00:00:00 +0000")

        let result = try runLifecycleCLI([
            "analyze", fixture.repository.path, "--format", "json",
            "--lifecycle-artifact", artifact.path, "--jobs", "2",
        ])
        #expect(result.status == 0)
        let migrated = try LifecycleArtifactStore(artifactURL: artifact).load()
        #expect(migrated.schemaVersion == 3)
        #expect(migrated.findings.count == 1)
        #expect(migrated.findings.first?.events.map(\.transition.kind) == [.opened, .resolved])
        #expect(migrated.unresolvedDetections.count == 1)
        #expect(migrated.unresolvedDetections.first?.reasons.map(\.code) == ["configuration-incomparable"])
        let inventory = try runLifecycleCLI(["lifecycle", "inventory", artifact.path])
        #expect(inventory.status == 0)
        #expect(inventory.standardOutput.contains("reasons=configuration-incomparable"))
    }

    private func datedCommit(
        _ fixture: TemporaryLifecycleGitRepository,
        source: String,
        message: String,
        date: String
    ) throws {
        try fixture.write(source: source)
        try fixture.runGit(["add", "Sources/Input.swift"])
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_AUTHOR_DATE"] = date
        environment["GIT_COMMITTER_DATE"] = date
        environment["GIT_AUTHOR_NAME"] = "Lifecycle Test"
        environment["GIT_AUTHOR_EMAIL"] = "lifecycle@example.test"
        environment["GIT_COMMITTER_NAME"] = "Lifecycle Test"
        environment["GIT_COMMITTER_EMAIL"] = "lifecycle@example.test"
        let result = try runLifecycleProcess(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", fixture.repository.path, "-c", "commit.gpgsign=false", "commit", "-m", message],
            directory: fixture.repository,
            environment: environment,
            mergeStandardError: true
        )
        #expect(result.status == 0)
    }
}
