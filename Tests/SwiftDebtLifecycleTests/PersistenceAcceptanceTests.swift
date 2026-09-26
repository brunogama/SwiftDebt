import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 persistence and ordering acceptance")
struct PersistenceAcceptanceTests {
    @Test("AT-21 explicit lineage order wins over arrival order")
    func outOfOrderArrivalProcessesInLineageOrder() throws {
        let orderedFixture = try TemporaryLifecycleArtifact()
        let reversedFixture = try TemporaryLifecycleArtifact()
        let root = try makeObservation(
            id: "ordered-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let child = try makeObservation(
            id: "ordered-child",
            sequence: 2,
            predecessor: "ordered-root",
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )

        let orderedStore = LifecycleArtifactStore(artifactURL: orderedFixture.url)
        _ = try orderedStore.ingest(root)
        _ = try orderedStore.ingest(child)

        let reversedStore = LifecycleArtifactStore(artifactURL: reversedFixture.url)
        let pending = try reversedStore.ingest(child)
        #expect(pending.processedSnapshotIDs.isEmpty)
        #expect(pending.artifact.findings.isEmpty)
        let completed = try reversedStore.ingest(root)
        #expect(completed.processedSnapshotIDs == [root.id, child.id])

        #expect(try Data(contentsOf: orderedFixture.url) == Data(contentsOf: reversedFixture.url))
        #expect(try reversedStore.load().findings.first?.lifecycleState == .resolved)
    }

    @Test("AT-21 divergent lineages keep independent Finding state")
    func divergentLineagesRemainIndependent() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let main = try makeObservation(
            id: "main-root",
            lineage: "main",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let feature = try makeObservation(
            id: "feature-root",
            lineage: "feature",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )

        _ = try store.ingest(main)
        _ = try store.ingest(feature)
        let artifact = try store.load()

        #expect(Set(artifact.findings.map(\.lineageID)) == Set([try LineageID("main"), try LineageID("feature")]))
        #expect(artifact.lineageHeads.count == 2)
        #expect(artifact.findings.allSatisfy { $0.lifecycleState == .open })
    }

    @Test("AT-22 repeated ingestion preserves bytes and creates no duplicates")
    func repeatedIngestionIsIdempotent() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "idempotent-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(2))]
        )

        let first = try store.ingest(snapshot)
        let firstBytes = try Data(contentsOf: fixture.url)
        let second = try store.ingest(snapshot)
        let secondBytes = try Data(contentsOf: fixture.url)

        #expect(first.status == .accepted)
        #expect(second.status == .alreadyPresent)
        #expect(firstBytes == secondBytes)
        #expect(second.artifact.snapshots.count == 1)
        #expect(second.artifact.findings.count == 2)
        #expect(second.artifact.findings.flatMap(\.events).count == 2)
    }

    @Test("Schema-1 snapshots derive selected rules from legacy Atomic Observations")
    func snapshotsWithoutSelectedRulesRemainReadable() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "legacy-rules-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(snapshot)

        var root = try artifactJSONObject(at: fixture.url)
        var snapshots = try #require(root["snapshots"] as? [[String: Any]])
        snapshots[0].removeValue(forKey: "rules")
        root["snapshots"] = snapshots
        try lifecycleJSONData(root).write(to: fixture.url, options: .atomic)

        let loaded = try store.load()
        #expect(loaded.snapshot(id: snapshot.id)?.rules == snapshot.rules)
    }

    @Test("Schema 1 lifecycle artifacts migrate in memory and write schema 2 only after accepted ingestion")
    func schemaOneLifecycleMigrationIsStrictAndAtomic() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let rootSnapshot = try makeObservation(
            id: "migration-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let childSnapshot = try makeObservation(
            id: "migration-child",
            sequence: 2,
            predecessor: "migration-root",
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        _ = try store.ingest(rootSnapshot)
        _ = try store.ingest(childSnapshot)
        let schemaTwo = try store.load()
        let findingID = try #require(schemaTwo.findings.first?.id)

        var schemaOne = try artifactJSONObject(at: fixture.url)
        schemaOne["schemaVersion"] = 1
        schemaOne.removeValue(forKey: "snapshotParentEdges")
        schemaOne["lineageHeads"] = try jsonObject(schemaTwo.lineageHeads)
        var findings = try #require(schemaOne["findings"] as? [[String: Any]])
        for findingIndex in findings.indices {
            var finding = findings[findingIndex]
            var events = try #require(finding["events"] as? [[String: Any]])
            for eventIndex in events.indices {
                events[eventIndex].removeValue(forKey: "basisEventIDs")
            }
            finding["events"] = events
            findings[findingIndex] = finding
        }
        schemaOne["findings"] = findings
        let schemaOneBytes = try lifecycleJSONData(schemaOne)
        try schemaOneBytes.write(to: fixture.url, options: .atomic)

        let migrated = try store.load()
        #expect(migrated.schemaVersion == 2)
        #expect(migrated.findings.first?.id == findingID)
        #expect(migrated.findings.first?.events.map(\.id) == schemaTwo.findings.first?.events.map(\.id))
        #expect(migrated.findings.first?.events.map(\.transition.kind) == [.opened, .resolved])
        #expect(try Data(contentsOf: fixture.url) == schemaOneBytes)

        let thirdSnapshot = try makeObservation(
            id: "migration-third",
            sequence: 3,
            predecessor: "migration-child",
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        #expect(try store.ingest(thirdSnapshot).status == .accepted)
        let persisted = try artifactJSONObject(at: fixture.url)
        #expect(persisted["schemaVersion"] as? Int == 2)
        #expect(persisted["snapshotParentEdges"] != nil)
        #expect(persisted["lineageHeads"] == nil)
        #expect(
            try store.load().findings.first?.events.map(\.transition.kind)
                == [.opened, .resolved, .reopened]
        )
    }

    @Test("A schema 1 artifact with a corrupt lineage head fails closed")
    func corruptSchemaOneLineageFailsClosed() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "migration-corrupt-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(snapshot)
        let artifact = try store.load()
        var schemaOne = try artifactJSONObject(at: fixture.url)
        schemaOne["schemaVersion"] = 1
        schemaOne.removeValue(forKey: "snapshotParentEdges")
        var heads = try #require(try jsonObject(artifact.lineageHeads) as? [[String: Any]])
        heads[0]["snapshotID"] = "missing-snapshot"
        schemaOne["lineageHeads"] = heads
        var findings = try #require(schemaOne["findings"] as? [[String: Any]])
        var events = try #require(findings[0]["events"] as? [[String: Any]])
        events[0].removeValue(forKey: "basisEventIDs")
        findings[0]["events"] = events
        schemaOne["findings"] = findings
        let corruptBytes = try lifecycleJSONData(schemaOne)
        try corruptBytes.write(to: fixture.url, options: .atomic)

        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fixture.url) == corruptBytes)
    }

    @Test("Schema 2 rejects sibling event leakage and broken graph parents")
    func corruptSnapshotGraphFailsClosed() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let rootSnapshot = try makeObservation(
            id: "graph-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let resolvedBranch = try makeObservation(
            id: "graph-resolved-branch",
            sequence: 2,
            predecessor: "graph-root",
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        let openBranch = try makeObservation(
            id: "graph-open-branch",
            sequence: 2,
            predecessor: "graph-root",
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(rootSnapshot)
        _ = try store.ingest(resolvedBranch)
        _ = try store.ingest(openBranch)
        let validBytes = try Data(contentsOf: fixture.url)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)
        let resolvedEvent = try #require(
            finding.events.first { $0.snapshotID == resolvedBranch.id }
        )

        var siblingLeak = try artifactJSONObject(at: fixture.url)
        var findings = try #require(siblingLeak["findings"] as? [[String: Any]])
        var events = try #require(findings[0]["events"] as? [[String: Any]])
        let openEventIndex = try #require(
            events.firstIndex { event in
                event["snapshotID"] as? String == openBranch.id.rawValue
            })
        events[openEventIndex]["basisEventIDs"] = [resolvedEvent.id.rawValue]
        findings[0]["events"] = events
        siblingLeak["findings"] = findings
        let siblingLeakBytes = try lifecycleJSONData(siblingLeak)
        try siblingLeakBytes.write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }

        try validBytes.write(to: fixture.url, options: .atomic)
        var brokenParent = try artifactJSONObject(at: fixture.url)
        var edges = try #require(brokenParent["snapshotParentEdges"] as? [[String: Any]])
        edges[0]["parentSnapshotID"] = "missing-parent"
        brokenParent["snapshotParentEdges"] = edges
        let brokenParentBytes = try lifecycleJSONData(brokenParent)
        try brokenParentBytes.write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fixture.url) == brokenParentBytes)
    }

    @Test("AT-24 unknown schema and broken references fail closed")
    func unreadableArtifactsAreRejectedWithoutReplacement() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "valid-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(snapshot)
        let validData = try Data(contentsOf: fixture.url)
        var root = try #require(JSONSerialization.jsonObject(with: validData) as? [String: Any])

        root["schemaVersion"] = LifecycleArtifactSchema.currentVersion + 1
        let unknownSchema = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try unknownSchema.write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fixture.url) == unknownSchema)

        root = try #require(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var findings = try #require(root["findings"] as? [[String: Any]])
        var finding = try #require(findings.first)
        var events = try #require(finding["events"] as? [[String: Any]])
        var event = try #require(events.first)
        var transition = try #require(event["transition"] as? [String: Any])
        var detection = try #require(transition["detection"] as? [String: Any])
        detection["detectionID"] = "missing-detection"
        transition["detection"] = detection
        event["transition"] = transition
        events[0] = event
        finding["events"] = events
        findings[0] = finding
        root["findings"] = findings
        let brokenReference = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try brokenReference.write(to: fixture.url, options: .atomic)

        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(throws: LifecycleStoreError.self) { try store.ingest(snapshot) }
        #expect(try Data(contentsOf: fixture.url) == brokenReference)
    }

}

private func jsonObject<Value: Encodable>(_ value: Value) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}
