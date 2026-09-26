import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("Schema 1 corruption CLI acceptance")
struct SchemaOneCorruptionCLIWorkflowTests {
    @Test("Schema 1 duplicate snapshot IDs return a CLI read error without trapping")
    func duplicateSchemaOneSnapshotsFailClosed() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "migration-duplicate-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(snapshot)
        let artifact = try store.load()

        var schemaOne = try artifactJSONObject(at: fixture.url)
        schemaOne["schemaVersion"] = 1
        schemaOne.removeValue(forKey: "snapshotParentEdges")
        schemaOne["lineageHeads"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(artifact.lineageHeads))
        var snapshots = try #require(schemaOne["snapshots"] as? [[String: Any]])
        snapshots.append(snapshots[0])
        schemaOne["snapshots"] = snapshots
        var findings = try #require(schemaOne["findings"] as? [[String: Any]])
        for index in findings.indices {
            var events = try #require(findings[index]["events"] as? [[String: Any]])
            for eventIndex in events.indices {
                events[eventIndex].removeValue(forKey: "basisEventIDs")
            }
            findings[index]["events"] = events
        }
        schemaOne["findings"] = findings
        try lifecycleJSONData(schemaOne).write(to: fixture.url, options: .atomic)

        let result = try runLifecycleCLI(["lifecycle", "inventory", fixture.url.path])
        #expect(result.status == 2)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("Schema 1 snapshot references are invalid."))
    }

}
