import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 concurrent lifecycle replay acceptance")
struct LifecycleConcurrentReplayAcceptanceTests {
    @Test("AT-22 concurrent and reordered ingestion has one canonical history")
    func concurrentReplayMatchesOrderedHistory() async throws {
        let snapshots = try [
            makeObservation(
                id: "replay-main-root",
                lineage: "main",
                sequence: 1,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            ),
            makeObservation(
                id: "replay-main-child",
                lineage: "main",
                sequence: 2,
                predecessor: "replay-main-root",
                rules: [LifecycleRuleV1(mode: .committed(0))]
            ),
            makeObservation(
                id: "replay-feature-root",
                lineage: "feature",
                sequence: 1,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            ),
            makeObservation(
                id: "replay-feature-child",
                lineage: "feature",
                sequence: 2,
                predecessor: "replay-feature-root",
                rules: [LifecycleRuleV1(mode: .committed(1))]
            ),
        ]

        let orderedFixture = try TemporaryLifecycleArtifact()
        let orderedStore = LifecycleArtifactStore(artifactURL: orderedFixture.url)
        for snapshot in snapshots { _ = try orderedStore.ingest(snapshot) }
        let expected = try Data(contentsOf: orderedFixture.url)

        for order in [[3, 1, 2, 0], [1, 3, 0, 2], [2, 0, 3, 1]] {
            let fixture = try TemporaryLifecycleArtifact()
            let store = LifecycleArtifactStore(artifactURL: fixture.url)
            let arrivals = order.map { snapshots[$0] }
            let statuses = try await withThrowingTaskGroup(
                of: SnapshotIngestionStatus.self,
                returning: [SnapshotIngestionStatus].self
            ) { group in
                for snapshot in arrivals + arrivals + arrivals {
                    group.addTask { try store.ingest(snapshot).status }
                }
                var results: [SnapshotIngestionStatus] = []
                for try await status in group { results.append(status) }
                return results
            }

            #expect(statuses.filter { $0 == .accepted }.count == snapshots.count)
            #expect(statuses.filter { $0 == .alreadyPresent }.count == snapshots.count * 2)
            #expect(try Data(contentsOf: fixture.url) == expected)
            let artifact = try store.load()
            #expect(artifact.snapshots.count == snapshots.count)
            #expect(artifact.findings.count == 2)
            #expect(artifact.lineageHeads.count == 2)
        }
    }
}
