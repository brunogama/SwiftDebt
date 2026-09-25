import SwiftDebtLifecycle
import Testing

@Suite("R3 conservative continuity acceptance")
struct ContinuitySafetyAcceptanceTests {
    @Test("A resolved Finding keeps verified absence when a later Detection is unresolved")
    func resolvedFindingDoesNotReceiveAmbiguousEvent() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let first = try makeObservation(
            id: "resolved-prior", sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let absent = try makeObservation(
            id: "resolved-absence", sequence: 2, predecessor: "resolved-prior",
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        let later = try makeObservation(
            id: "resolved-later", sequence: 3, predecessor: "resolved-absence",
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )

        _ = try store.ingest(first)
        _ = try store.ingest(absent)
        _ = try store.ingest(later)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)

        #expect(finding.lifecycleState == .resolved)
        #expect(finding.evidenceState == .verifiedAbsent)
        #expect(finding.events.map(\.transition.kind) == [.opened, .resolved])
        #expect(artifact.unresolvedDetections.count == 1)
    }

    @Test("AT-5 one prior Detection copied to two successors remains ambiguous")
    func oneToManyRemainsAmbiguous() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "copy-original",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let copied = try makeObservation(
            id: "copy-successors",
            sequence: 2,
            predecessor: "copy-original",
            rules: [LifecycleRuleV1(mode: .committed(2))]
        )

        _ = try store.ingest(original)
        _ = try store.ingest(copied)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)

        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 2)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .continuityAmbiguous)
        #expect(artifact.unresolvedDetections.allSatisfy { $0.candidateFindingIDs == [finding.id] })
    }

    @Test("AT-6 two prior Findings collapsing to one Detection remain ambiguous")
    func manyToOneRemainsAmbiguous() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let originals = try makeObservation(
            id: "merge-originals",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(2))]
        )
        let collapsed = try makeObservation(
            id: "merge-successor",
            sequence: 2,
            predecessor: "merge-originals",
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )

        _ = try store.ingest(originals)
        _ = try store.ingest(collapsed)
        let artifact = try store.load()
        let unresolved = try #require(artifact.unresolvedDetections.first)

        #expect(artifact.findings.count == 2)
        #expect(artifact.findings.allSatisfy { $0.lifecycleState == .open })
        #expect(artifact.findings.allSatisfy { $0.evidenceState == .continuityAmbiguous })
        #expect(unresolved.candidateFindingIDs == artifact.findings.map(\.id))
    }

    @Test("AT-12 a changed Semantic Revision cannot continue or resolve a Finding")
    func semanticRevisionChangeFailsClosed() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let revisionOne = try makeObservation(
            id: "semantic-v1",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let revisionTwo = try makeObservation(
            id: "semantic-v2",
            sequence: 2,
            predecessor: "semantic-v1",
            rules: [LifecycleRuleV2(mode: .committed(1))]
        )

        _ = try store.ingest(revisionOne)
        _ = try store.ingest(revisionTwo)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)
        let unresolved = try #require(artifact.unresolvedDetections.first)

        #expect(artifact.findings.count == 1)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .unverified)
        #expect(unresolved.reasons.map(\.code) == ["semantic-revision-incomparable"])
    }

    @Test("AT-27 exact location reuse does not establish continuity")
    func locationReuseDoesNotContinueFinding() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let prior = try makeObservation(
            id: "location-prior",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let unrelated = try makeObservation(
            id: "location-reused",
            sequence: 2,
            predecessor: "location-prior",
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let priorLocation = try #require(prior.detections.first?.location)
        let reusedLocation = try #require(unrelated.detections.first?.location)
        #expect(priorLocation == reusedLocation)

        _ = try store.ingest(prior)
        _ = try store.ingest(unrelated)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)

        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 1)
        #expect(finding.events.map(\.transition.kind) == [.opened, .continuityAmbiguous])
        #expect(finding.openingDetectionID == prior.detections.first?.id)
        #expect(artifact.unresolvedDetections.first?.detectionID == unrelated.detections.first?.id)
    }
}
