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
