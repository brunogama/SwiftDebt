import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 Semantic Revision compatibility CLI acceptance")
struct SemanticCompatibilityCLIWorkflowTests {
    @Test("AT-13 declared forward continuity does not authorize absence")
    func directionalClaimSpecificCompatibility() throws {
        let continuityFixture = try TemporaryLifecycleArtifact()
        let continuityStore = LifecycleArtifactStore(artifactURL: continuityFixture.url)
        let original = try makeObservation(
            id: "semantic-compatible-v1",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let continued = try makeObservation(
            id: "semantic-compatible-v2",
            sequence: 2,
            predecessor: original.id.rawValue,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(1))]
        )

        _ = try continuityStore.ingest(original)
        _ = try continuityStore.ingest(continued)
        let continuedArtifact = try continuityStore.load()
        let continuedFinding = try #require(continuedArtifact.findings.first)
        let continuedEvent = try #require(continuedFinding.events.last)

        #expect(continuedArtifact.findings.count == 1)
        #expect(continuedFinding.events.map(\.transition.kind) == [.opened, .observed])
        #expect(continuedEvent.semanticComparisons.count == 1)
        #expect(continuedEvent.semanticComparisons.first?.claim == .continuity)
        #expect(continuedEvent.semanticComparisons.first?.decision == .compatible)
        #expect(
            continuedEvent.semanticComparisons.first?.compatibilityDeclaration?.supportedClaims
                == [.continuity]
        )
        let selectedRule = try #require(continued.rules.first)
        #expect(selectedRule.compatibilityDeclarations.count == 1)
        #expect(
            SnapshotRule(
                identity: selectedRule.identity,
                semanticRevision: selectedRule.semanticRevision
            ).compatibilityDeclarations.isEmpty
        )

        let continuityExplanation = try runLifecycleCLI([
            "lifecycle", "explain", continuityFixture.url.path, continuedFinding.id.rawValue,
        ])
        #expect(continuityExplanation.status == 0)
        #expect(continuityExplanation.standardOutput.contains("semantic-compatibility-declared"))
        #expect(continuityExplanation.standardOutput.contains("continuity revisions=1->2 compatible"))
        let snapshotInspection = try runLifecycleCLI([
            "lifecycle", "snapshot", continuityFixture.url.path, continued.id.rawValue,
        ])
        #expect(snapshotInspection.status == 0)
        #expect(snapshotInspection.standardOutput.contains("Semantic compatibility:"))
        #expect(snapshotInspection.standardOutput.contains("revisions=1->2 claims=continuity"))

        let absenceFixture = try TemporaryLifecycleArtifact()
        let absenceStore = LifecycleArtifactStore(artifactURL: absenceFixture.url)
        let absenceRoot = try makeObservation(
            id: "semantic-absence-v1",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let absentUnderV2 = try makeObservation(
            id: "semantic-absence-v2",
            sequence: 2,
            predecessor: absenceRoot.id.rawValue,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(0))]
        )

        _ = try absenceStore.ingest(absenceRoot)
        _ = try absenceStore.ingest(absentUnderV2)
        let absenceArtifact = try absenceStore.load()
        let unresolvedFinding = try #require(absenceArtifact.findings.first)
        let unverifiedEvent = try #require(unresolvedFinding.events.last)

        #expect(unresolvedFinding.lifecycleState == .open)
        #expect(unresolvedFinding.evidenceState == .unverified)
        #expect(unverifiedEvent.semanticComparisons.count == 1)
        #expect(unverifiedEvent.semanticComparisons.first?.claim == .absence)
        #expect(unverifiedEvent.semanticComparisons.first?.decision == .blocked)
        guard case .unverified(let reasons) = unverifiedEvent.transition else {
            Issue.record("Expected claim-specific absence to remain unverified")
            return
        }
        #expect(reasons.map(\.code).contains("semantic-absence-not-declared"))

        let absenceExplanation = try runLifecycleCLI([
            "lifecycle", "explain", absenceFixture.url.path, unresolvedFinding.id.rawValue,
        ])
        #expect(absenceExplanation.status == 0)
        #expect(absenceExplanation.standardOutput.contains("semantic-absence-not-declared"))
        #expect(absenceExplanation.standardOutput.contains("absence revisions=1->2 blocked"))
    }

    @Test("AT-13 undeclared and reverse comparisons remain blocked")
    func undeclaredAndReverseComparisonsFailClosed() throws {
        let undeclaredFixture = try TemporaryLifecycleArtifact()
        let undeclaredStore = LifecycleArtifactStore(artifactURL: undeclaredFixture.url)
        let revisionOne = try makeObservation(
            id: "semantic-undeclared-v1",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let undeclaredRevisionTwo = try makeObservation(
            id: "semantic-undeclared-v2",
            sequence: 2,
            predecessor: revisionOne.id.rawValue,
            rules: [LifecycleRuleV2(mode: .committed(1))]
        )
        _ = try undeclaredStore.ingest(revisionOne)
        _ = try undeclaredStore.ingest(undeclaredRevisionTwo)

        let undeclaredFinding = try #require(undeclaredStore.load().findings.first)
        let undeclaredEvent = try #require(undeclaredFinding.events.last)
        guard case .unverified(let undeclaredReasons) = undeclaredEvent.transition else {
            Issue.record("Expected an undeclared revision change to remain unverified")
            return
        }
        #expect(undeclaredReasons.map(\.code).contains("semantic-revision-incomparable"))
        #expect(undeclaredEvent.semanticComparisons.first?.decision == .blocked)
        #expect(undeclaredEvent.semanticComparisons.first?.compatibilityDeclaration == nil)

        let reverseFixture = try TemporaryLifecycleArtifact()
        let reverseStore = LifecycleArtifactStore(artifactURL: reverseFixture.url)
        let revisionTwo = try makeObservation(
            id: "semantic-reverse-v2",
            sequence: 1,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(1))]
        )
        let reverseRevisionOne = try makeObservation(
            id: "semantic-reverse-v1",
            sequence: 2,
            predecessor: revisionTwo.id.rawValue,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try reverseStore.ingest(revisionTwo)
        _ = try reverseStore.ingest(reverseRevisionOne)

        let reverseFinding = try #require(reverseStore.load().findings.first)
        let reverseEvent = try #require(reverseFinding.events.last)
        guard case .unverified(let reverseReasons) = reverseEvent.transition else {
            Issue.record("Expected reverse compatibility to remain unverified")
            return
        }
        #expect(reverseReasons.map(\.code).contains("semantic-revision-incomparable"))
        #expect(reverseEvent.semanticComparisons.first?.priorRule.semanticRevision.rawValue == 2)
        #expect(reverseEvent.semanticComparisons.first?.currentRule.semanticRevision.rawValue == 1)
        #expect(reverseEvent.semanticComparisons.first?.decision == .blocked)

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", reverseFixture.url.path, reverseFinding.id.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("continuity revisions=2->1 blocked"))
        #expect(explanation.standardOutput.contains("semantic-revision-incomparable"))
    }

    @Test("A persisted compatibility decision is recomputed and fails closed")
    func tamperedComparisonBasisIsRejected() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let first = try makeObservation(
            id: "semantic-proof-v1",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let second = try makeObservation(
            id: "semantic-proof-v2",
            sequence: 2,
            predecessor: first.id.rawValue,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(1))]
        )
        _ = try store.ingest(first)
        _ = try store.ingest(second)

        var root = try artifactJSONObject(at: fixture.url)
        var findings = try #require(root["findings"] as? [[String: Any]])
        var finding = try #require(findings.first)
        var events = try #require(finding["events"] as? [[String: Any]])
        var continuedEvent = try #require(events.last)
        continuedEvent.removeValue(forKey: "semanticComparisons")
        events[events.count - 1] = continuedEvent
        finding["events"] = events
        findings[0] = finding
        root["findings"] = findings

        let corrupted = try lifecycleJSONData(root)
        try corrupted.write(to: fixture.url, options: .atomic)
        #expect(throws: LifecycleStoreError.self) { try store.load() }
        #expect(try Data(contentsOf: fixture.url) == corrupted)
    }
}
