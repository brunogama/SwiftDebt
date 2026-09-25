import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 read-only CLI acceptance")
struct LifecycleCLIWorkflowTests {
    @Test("Lifecycle CLI rejects duplicate format options")
    func duplicateFormatFails() throws {
        let result = try runLifecycleCLI([
            "lifecycle", "inventory", "missing.json", "--format", "text", "--format=json",
        ])
        #expect(result.status == 2)
        #expect(result.standardError.contains("Duplicate option: --format"))
    }

    @Test("Persisted lifecycle artifact supports inventory, explanation, and snapshot inspection")
    func readOnlyCommandsInspectPersistedEvidence() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "cli-original",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let ambiguous = try makeObservation(
            id: "cli-ambiguous",
            sequence: 2,
            predecessor: "cli-original",
            rules: [LifecycleRuleV1(mode: .committed(2))]
        )
        _ = try store.ingest(original)
        _ = try store.ingest(ambiguous)
        let findingID = try #require(store.load().findings.first?.id)
        let bytesBefore = try Data(contentsOf: fixture.url)

        let inventory = try runLifecycleCLI([
            "lifecycle", "inventory", fixture.url.path, "--format", "json",
        ])
        #expect(inventory.status == 0)
        #expect(inventory.standardError.isEmpty)
        let inventoryReport = try JSONDecoder().decode(
            LifecycleInventoryReport.self,
            from: Data(inventory.standardOutput.utf8)
        )
        #expect(inventoryReport.reportKind == "swiftdebt-lifecycle-inventory")
        #expect(inventoryReport.findings.first?.evidenceState == .continuityAmbiguous)
        #expect(inventoryReport.unresolvedDetections.count == 2)

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.url.path, findingID.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("continuity-evidence-unavailable"))
        #expect(explanation.standardOutput.contains("no predecessor was selected"))

        let inspection = try runLifecycleCLI([
            "lifecycle", "snapshot", fixture.url.path, ambiguous.id.rawValue,
        ])
        #expect(inspection.status == 0)
        #expect(inspection.standardOutput.contains("Snapshot cli-ambiguous"))
        #expect(inspection.standardOutput.contains("Atomic observations complete: true"))
        #expect(try Data(contentsOf: fixture.url) == bytesBefore)
    }

    @Test("Read-only CLI rejects an unknown lifecycle schema")
    func cliFailsClosedForUnknownSchema() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "cli-schema",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        _ = try store.ingest(snapshot)
        var root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.url)) as? [String: Any]
        )
        root["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: root).write(to: fixture.url, options: .atomic)

        let result = try runLifecycleCLI(["lifecycle", "inventory", fixture.url.path])

        #expect(result.status == 2)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("Unsupported lifecycle artifact schema version 99"))
    }
}
