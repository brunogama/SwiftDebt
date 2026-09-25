import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 persisted proof validation")
struct ArtifactProofValidationTests {
    @Test("AT-24 a reference-valid resolution must still prove complete absence")
    func invalidResolutionProofIsRejected() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let observed = try makeObservation(
            id: "proof-root",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let absent = try makeObservation(
            id: "proof-child",
            sequence: 2,
            predecessor: "proof-root",
            rules: [LifecycleRuleV1(mode: .committed(0)), AlwaysFailingRule()]
        )
        _ = try store.ingest(observed)
        _ = try store.ingest(absent)

        var root = try artifactJSONObject(at: fixture.url)
        let snapshots = try #require(root["snapshots"] as? [[String: Any]])
        let resolvingSnapshot = try #require(snapshots.first(where: { $0["id"] as? String == "proof-child" }))
        let atomics = try #require(resolvingSnapshot["atomicObservations"] as? [[String: Any]])
        let failedAtomic = try #require(
            atomics.first(where: { atomic in
                guard let outcome = atomic["outcome"] as? [String: Any] else { return false }
                return outcome["kind"] as? String == "failed"
            })
        )
        let wrongAtomicID = try #require(failedAtomic["id"] as? String)

        var findings = try #require(root["findings"] as? [[String: Any]])
        var finding = try #require(findings.first)
        var events = try #require(finding["events"] as? [[String: Any]])
        var resolvedEvent = try #require(events.last)
        var transition = try #require(resolvedEvent["transition"] as? [String: Any])
        var resolution = try #require(transition["resolution"] as? [String: Any])
        resolution["coveredAtomicObservationIDs"] = [wrongAtomicID]
        transition["resolution"] = resolution
        resolvedEvent["transition"] = transition
        events[events.count - 1] = resolvedEvent
        finding["events"] = events
        findings[0] = finding
        root["findings"] = findings

        let corrupted = try lifecycleJSONData(root)
        try corrupted.write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fixture.url) == corrupted)
    }

    @Test("AT-24 continuity ambiguity rejects an unknown candidate Finding")
    func ambiguityWithBrokenCandidateReferenceIsRejected() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        _ = try store.ingest(
            makeObservation(
                id: "candidate-root",
                sequence: 1,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            )
        )
        _ = try store.ingest(
            makeObservation(
                id: "candidate-child",
                sequence: 2,
                predecessor: "candidate-root",
                rules: [LifecycleRuleV1(mode: .committed(1))]
            )
        )

        var root = try artifactJSONObject(at: fixture.url)
        var findings = try #require(root["findings"] as? [[String: Any]])
        var finding = try #require(findings.first)
        var events = try #require(finding["events"] as? [[String: Any]])
        var ambiguousEvent = try #require(events.last)
        var transition = try #require(ambiguousEvent["transition"] as? [String: Any])
        var ambiguity = try #require(transition["ambiguity"] as? [String: Any])
        ambiguity["candidateFindingIDs"] = ["missing-finding"]
        transition["ambiguity"] = ambiguity
        ambiguousEvent["transition"] = transition
        events[events.count - 1] = ambiguousEvent
        finding["events"] = events
        findings[0] = finding
        root["findings"] = findings

        try lifecycleJSONData(root).write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
    }

    @Test("AT-24 a processed Detection cannot disappear from derived state")
    func missingDetectionDispositionIsRejected() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        _ = try store.ingest(
            makeObservation(
                id: "disposition-root",
                sequence: 1,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            )
        )
        var root = try artifactJSONObject(at: fixture.url)
        root["findings"] = []
        try lifecycleJSONData(root).write(to: fixture.url, options: .atomic)

        #expect(throws: LifecycleStoreError.self) { try store.load() }
    }
}
