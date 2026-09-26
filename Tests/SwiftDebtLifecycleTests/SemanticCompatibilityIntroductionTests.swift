import SwiftDebtLifecycle
import Testing

@Suite("R3 Semantic Revision compatibility for introduction")
struct SemanticCompatibilityIntroductionTests {
    @Test("Introduction uses continuity and absence compatibility independently")
    func introductionComparisonsAreClaimSpecific() throws {
        let positive = try makeIntroductionFixture(parentDetectionCount: 1, name: "positive")
        let positiveRecording = try positive.store.recordIntroduction(
            positive.evidence,
            for: positive.findingID
        )

        #expect(positiveRecording.conclusion.kind == .exact)
        #expect(positiveRecording.conclusion.exactRevision == positive.parentRevision)
        guard
            let continuity = positiveRecording.conclusion.semanticComparisons.first(where: {
                $0.claim == .continuity
                    && $0.priorRule.semanticRevision == .initial
                    && $0.currentRule.semanticRevision.rawValue == 2
            })
        else {
            Issue.record("Expected the historical continuity comparison basis")
            return
        }
        #expect(continuity.decision == .compatible)

        let absent = try makeIntroductionFixture(parentDetectionCount: 0, name: "absent")
        let absentRecording = try absent.store.recordIntroduction(
            absent.evidence,
            for: absent.findingID
        )

        #expect(absentRecording.conclusion.kind == .bounded)
        #expect(absentRecording.conclusion.exactRevision == nil)
        #expect(
            absentRecording.conclusion.reasons.map(\.code)
                .contains("semantic-absence-not-declared")
        )
        guard
            let absence = absentRecording.conclusion.semanticComparisons.first(where: {
                $0.claim == .absence
                    && $0.priorRule.semanticRevision == .initial
                    && $0.currentRule.semanticRevision.rawValue == 2
            })
        else {
            Issue.record("Expected the historical absence comparison basis")
            return
        }
        #expect(absence.decision == .blocked)

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", absent.fixture.url.path, absent.findingID.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("semantic-absence-not-declared"))
        #expect(explanation.standardOutput.contains("absence revisions=1->2 blocked"))
    }

    private func makeIntroductionFixture(
        parentDetectionCount: Int,
        name: String
    ) throws -> IntroductionFixture {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let parentRevision = try GitRevisionID(String(repeating: "a", count: 40))
        let childRevision = try GitRevisionID(String(repeating: "b", count: 40))
        let childSource = "func run() { let value = 1 }\n"
        let childIdentity = SnapshotSourceIdentity.git(
            revision: childRevision,
            workingTreeState: .clean,
            contentDigest: try lifecycleDigest(for: childSource)
        )
        let opening = try makeObservation(
            id: "semantic-introduction-\(name)-opening",
            sequence: 1,
            sourceIdentity: childIdentity,
            source: childSource,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(1))]
        )
        _ = try store.ingest(opening)
        let findingID = try #require(store.load().findings.first?.id)

        let historicalChild = try makeObservation(
            id: "semantic-introduction-\(name)-child",
            lineage: "history-\(childRevision.rawValue)",
            sequence: 1,
            sourceIdentity: childIdentity,
            source: childSource,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(1))]
        )
        let parentSource = "func run() { let value = 0 }\n"
        let parentIdentity = SnapshotSourceIdentity.git(
            revision: parentRevision,
            workingTreeState: .clean,
            contentDigest: try lifecycleDigest(for: parentSource)
        )
        let historicalParent = try makeObservation(
            id: "semantic-introduction-\(name)-parent",
            lineage: "history-\(parentRevision.rawValue)",
            sequence: 1,
            sourceIdentity: parentIdentity,
            source: parentSource,
            rules: [LifecycleRuleV1(mode: .committed(parentDetectionCount))]
        )
        let boundary = IntroductionHistoryBoundary(
            startingRevision: childRevision,
            repositoryHeadRevision: childRevision,
            workingTreeState: .clean,
            workingTreeStatusDigest: try lifecycleDigest(for: "clean"),
            isShallow: false,
            maximumRevisions: 2,
            frontierRevisions: []
        )
        let evidence = IntroductionHistoryEvidence(
            boundary: boundary,
            revisions: [
                IntroductionHistoryRevision(
                    revision: childRevision,
                    parentRevisions: [parentRevision],
                    observation: historicalChild
                ),
                IntroductionHistoryRevision(
                    revision: parentRevision,
                    parentRevisions: [],
                    observation: historicalParent
                ),
            ]
        )
        return IntroductionFixture(
            fixture: fixture,
            store: store,
            findingID: findingID,
            parentRevision: parentRevision,
            evidence: evidence
        )
    }
}

private struct IntroductionFixture {
    let fixture: TemporaryLifecycleArtifact
    let store: LifecycleArtifactStore
    let findingID: FindingID
    let parentRevision: GitRevisionID
    let evidence: IntroductionHistoryEvidence
}
