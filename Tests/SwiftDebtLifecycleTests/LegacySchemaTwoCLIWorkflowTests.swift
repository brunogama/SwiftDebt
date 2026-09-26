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

    @Test("New directional continuity can extend a migrated schema 2 Finding")
    func directionalContinuityExtendsLegacyFinding() throws {
        let temporary = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: temporary.url)
        let original = try makeObservation(
            id: "legacy-directional-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(original)
        let openingID = try #require(store.load().findings.first?.events.first?.id)

        var legacy = try artifactJSONObject(at: temporary.url)
        legacy["schemaVersion"] = 2
        legacy.removeValue(forKey: "legacyProcessedSnapshotIDs")
        var findings = try #require(legacy["findings"] as? [[String: Any]])
        var events = try #require(findings[0]["events"] as? [[String: Any]])
        events[0].removeValue(forKey: "evidenceContract")
        findings[0]["events"] = events
        legacy["findings"] = findings
        try lifecycleJSONData(legacy).write(to: temporary.url, options: .atomic)

        let continued = try makeObservation(
            id: "legacy-directional-child",
            sequence: 2,
            predecessor: original.id.rawValue,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(1))]
        )
        #expect(try store.ingest(continued).status == .accepted)
        let persisted = try store.load()
        let finding = try #require(persisted.findings.first)
        #expect(persisted.findings.count == 1)
        #expect(finding.events.map(\.transition.kind) == [.opened, .observed])
        #expect(finding.events.first?.id == openingID)
        #expect(finding.events.map(\.evidenceContract) == [.legacySchemaTwo, .semanticComparisonV1])
        #expect(finding.events.first?.semanticComparisons.isEmpty == true)
        #expect(finding.events.last?.semanticComparisons.first?.claim == .continuity)
        #expect(finding.events.last?.semanticComparisons.first?.decision == .compatible)

        var corrupted = try artifactJSONObject(at: temporary.url)
        var tamperedFindings = try #require(corrupted["findings"] as? [[String: Any]])
        var tamperedEvents = try #require(tamperedFindings[0]["events"] as? [[String: Any]])
        let newEventIndex = try #require(
            tamperedEvents.firstIndex { $0["snapshotID"] as? String == continued.id.rawValue }
        )
        tamperedEvents[newEventIndex]["evidenceContract"] = "legacy-schema-2"
        tamperedFindings[0]["events"] = tamperedEvents
        corrupted["findings"] = tamperedFindings
        var legacyIDs = try #require(corrupted["legacyProcessedSnapshotIDs"] as? [String])
        legacyIDs.append(continued.id.rawValue)
        corrupted["legacyProcessedSnapshotIDs"] = legacyIDs
        try lifecycleJSONData(corrupted).write(to: temporary.url, options: .atomic)
        let rejected = try runLifecycleCLI(["lifecycle", "inventory", temporary.url.path])
        #expect(rejected.status == 2)
        #expect(rejected.standardOutput.isEmpty)
        #expect(rejected.standardError.contains("migration boundary"))
    }
}
