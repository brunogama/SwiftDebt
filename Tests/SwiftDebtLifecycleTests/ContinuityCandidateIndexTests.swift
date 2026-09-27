import Foundation
import SwiftDebtCore
import SwiftDebtSyntax
import Testing

@testable import SwiftDebtLifecycle

@Suite("R3 indexed continuity candidates")
struct ContinuityCandidateIndexTests {
    @Test("Distinct structural anchors avoid the Cartesian relation scan")
    func distinctAnchorsKeepUniqueContinuity() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let initial = try observation(id: "indexed-first", sequence: 1)
        let successor = try observation(
            id: "indexed-second", sequence: 2, predecessor: initial.id.rawValue
        )
        _ = try store.ingest(initial)
        let artifact = try store.load()

        let reconciliation = try ContinuityReconciler().reconcile(
            findings: artifact.findings,
            detections: successor.detections,
            snapshot: successor,
            artifact: artifact
        )

        #expect(reconciliation.matches.count == 8)
        #expect(reconciliation.unresolvedGroups.isEmpty)
        #expect(reconciliation.newDetections.isEmpty)
        #expect(reconciliation.absentFindings.isEmpty)
        #expect(reconciliation.evaluatedPairs == 8)
        #expect(reconciliation.crediblePairs == 8)
        #expect(Set(reconciliation.matches.map(\.finding.id)).count == 8)
    }

    @Test("Blocked semantic comparison still retains every uncertain pair")
    func incompatibleSemanticsKeepAllPairs() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let initial = try observation(id: "indexed-incompatible-first", sequence: 1, count: 2)
        let successor = try observation(
            id: "indexed-incompatible-second",
            sequence: 2,
            predecessor: initial.id.rawValue,
            count: 2,
            rule: IncompatibleNamedFunctionRule()
        )
        _ = try store.ingest(initial)
        let artifact = try store.load()

        let reconciliation = try ContinuityReconciler().reconcile(
            findings: artifact.findings,
            detections: successor.detections,
            snapshot: successor,
            artifact: artifact
        )

        #expect(reconciliation.matches.isEmpty)
        #expect(reconciliation.evaluatedPairs == 4)
        #expect(reconciliation.crediblePairs == 4)
        #expect(reconciliation.unresolvedGroups.count == 1)
        #expect(reconciliation.unresolvedGroups.first?.isAmbiguous == false)
        #expect(reconciliation.unresolvedGroups.first?.findings.count == 2)
        #expect(reconciliation.unresolvedGroups.first?.detections.count == 2)
    }

    @Test("Incomplete current structural evidence remains a candidate across paths")
    func incompleteEvidenceIsNeverFiltered() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let initial = try observation(id: "indexed-incomplete-first", sequence: 1, count: 2)
        let successor = try observation(
            id: "indexed-incomplete-second", sequence: 2,
            predecessor: initial.id.rawValue, count: 2
        )
        _ = try store.ingest(initial)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)
        let prior = try #require(initial.detection(id: finding.latestDetectionReference.detectionID))
        let current = try #require(successor.detections.last)
        let withoutEvidence = try ObservedDetection(
            id: current.id,
            rule: current.rule,
            severity: current.severity,
            location: current.location,
            message: current.message
        )
        let detections = [try #require(successor.detections.first), withoutEvidence]
        let candidate = Candidate(finding: finding, snapshot: initial, detection: prior)
        let index = ContinuityCandidateIndex(detections: detections)

        #expect(
            index.possibleDetections(
                for: candidate,
                currentRule: current.rule,
                semanticsCompatible: true
            ) == [0, 1])
        let relation = try ContinuityReconciler().relation(
            candidate: candidate,
            detection: withoutEvidence,
            snapshot: successor
        )
        guard case .ambiguous(let reasons, _) = relation else {
            Issue.record("Missing current evidence must remain ambiguous.")
            return
        }
        #expect(reasons.map(\.code).contains("continuity-evidence-unavailable"))
    }

    @Test("Disconnected same-source edits remain unresolved")
    func sameSourceDivergenceCountsFallbackPair() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let initial = try makeObservation(
            id: "indexed-divergence-first", sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let successor = try makeObservation(
            id: "indexed-divergence-second", sequence: 2,
            predecessor: initial.id.rawValue,
            source: "var first = 1\nlet second = 2\n",
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(initial)
        let artifact = try store.load()

        let reconciliation = try ContinuityReconciler().reconcile(
            findings: artifact.findings,
            detections: successor.detections,
            snapshot: successor,
            artifact: artifact
        )

        #expect(reconciliation.evaluatedPairs == 1)
        #expect(reconciliation.crediblePairs == 1)
        #expect(
            reconciliation.unresolvedGroups.first?.reasons.map(\.code)
                == ["same-source-structural-divergence"])
    }

    @Test("Same-source partial digest evidence is assessed once")
    func sameSourcePartialDigestCountsOnce() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let initial = try makeObservation(
            id: "indexed-partial-first", sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let successor = try makeObservation(
            id: "indexed-partial-second", sequence: 2,
            predecessor: initial.id.rawValue,
            source: "let first = 3\nlet second = 2\n",
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        _ = try store.ingest(initial)
        let artifact = try store.load()

        let reconciliation = try ContinuityReconciler().reconcile(
            findings: artifact.findings,
            detections: successor.detections,
            snapshot: successor,
            artifact: artifact
        )

        #expect(reconciliation.evaluatedPairs == 1)
        #expect(reconciliation.crediblePairs == 1)
        #expect(
            reconciliation.unresolvedGroups.first?.reasons.map(\.code)
                == ["enclosing-declaration-changed"])
    }

    private func observation(
        id: String,
        sequence: UInt,
        predecessor: String? = nil,
        count: Int = 8,
        rule: any DebtRule = NamedFunctionRule()
    ) throws -> ObservationSnapshot {
        let sources = (0..<count).map { index in
            SourceUnit(
                path: String(format: "Sources/File%04d.swift", index),
                content: String(format: "func operation%04d() { try! work() }\n", index)
            )
        }
        let analysis = try RuleEngine().analyze(sources, using: [rule])
        return try ObservationSnapshot(
            id: SnapshotID(id),
            provenance: SnapshotProvenance(
                sourceIdentity: .contentDigest(lifecycleDigest(for: "indexed-source")),
                scope: .repository,
                configurationFingerprint: lifecycleDigest(for: "indexed-configuration"),
                capabilities: [],
                engineVersion: "test-engine",
                lineage: LineagePosition(
                    lineageID: LineageID("main"),
                    sequence: sequence,
                    predecessorSnapshotID: try predecessor.map(SnapshotID.init)
                )
            ),
            analysis: analysis
        )
    }
}
