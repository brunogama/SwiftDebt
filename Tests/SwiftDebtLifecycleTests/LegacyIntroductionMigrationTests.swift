import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 legacy introduction migration")
struct LegacyIntroductionMigrationTests {
    @Test("A schema 2 Introduction Conclusion retains its historical claim without a new basis")
    func legacyConclusionRemainsReadable() throws {
        let temporary = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: temporary.url)
        let revision = try GitRevisionID(String(repeating: "a", count: 40))
        let source = "func run() { let value = 1 }\n"
        let identity = SnapshotSourceIdentity.git(
            revision: revision,
            workingTreeState: .clean,
            contentDigest: try lifecycleDigest(for: source)
        )
        let opening = try makeObservation(
            id: "legacy-introduction-opening",
            sequence: 1,
            sourceIdentity: identity,
            source: source,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(opening)
        let findingID = try #require(store.load().findings.first?.id)
        let historical = try makeObservation(
            id: "legacy-introduction-history",
            lineage: "history-\(revision.rawValue)",
            sequence: 1,
            sourceIdentity: identity,
            source: source,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let boundary = IntroductionHistoryBoundary(
            startingRevision: revision,
            repositoryHeadRevision: revision,
            workingTreeState: .clean,
            workingTreeStatusDigest: try lifecycleDigest(for: "clean"),
            isShallow: false,
            maximumRevisions: 1,
            frontierRevisions: []
        )
        let evidence = IntroductionHistoryEvidence(
            boundary: boundary,
            revisions: [
                IntroductionHistoryRevision(revision: revision, parentRevisions: [], observation: historical)
            ]
        )
        let currentConclusion = try store.recordIntroduction(evidence, for: findingID).conclusion
        #expect(currentConclusion.kind == .exact)

        var legacy = try artifactJSONObject(at: temporary.url)
        legacy["schemaVersion"] = 2
        legacy.removeValue(forKey: "legacyProcessedSnapshotIDs")
        var findings = try #require(legacy["findings"] as? [[String: Any]])
        var events = try #require(findings[0]["events"] as? [[String: Any]])
        events[0].removeValue(forKey: "evidenceContract")
        findings[0]["events"] = events
        legacy["findings"] = findings
        var conclusions = try #require(legacy["introductionConclusions"] as? [[String: Any]])
        conclusions[0].removeValue(forKey: "evidenceContract")
        conclusions[0].removeValue(forKey: "semanticComparisons")
        legacy["introductionConclusions"] = conclusions
        let original = try lifecycleJSONData(legacy)
        try original.write(to: temporary.url, options: .atomic)

        let migrated = try store.load()
        let conclusion = try #require(migrated.introductionConclusions.first)
        #expect(conclusion.evidenceContract == .legacySchemaTwo)
        #expect(conclusion.semanticComparisons.isEmpty)
        #expect(conclusion.kind == currentConclusion.kind)
        #expect(conclusion.exactRevision == currentConclusion.exactRevision)
        #expect(conclusion.reasons == currentConclusion.reasons)
        #expect(try Data(contentsOf: temporary.url) == original)
    }
}
