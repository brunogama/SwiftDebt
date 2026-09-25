import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 Atomic Observation acceptance")
struct AtomicObservationAcceptanceTests {
    @Test("AT-1 keeps a committed Detection when another rule fails")
    func positiveObservationSurvivesPartialSnapshot() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let snapshot = try makeObservation(
            id: "partial-positive",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1)), AlwaysFailingRule()]
        )

        #expect(!snapshot.isAtomicallyComplete)
        #expect(!snapshot.supportsRepositoryAbsence)
        #expect(snapshot.detections.count == 1)
        #expect(snapshot.atomicObservations.map(\.outcome.kind) == [.failed, .committed])

        _ = try LifecycleArtifactStore(artifactURL: fixture.url).ingest(snapshot)
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.url).load()
        let finding = try #require(persisted.findings.first)

        #expect(persisted.snapshots == [snapshot])
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .observed)
    }

    @Test("AT-2 committed zero is pair-level absence under partial scope")
    func committedZeroProvesAtomicAbsence() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let snapshot = try makeObservation(
            id: "pair-absence",
            sequence: 1,
            scope: .partial(
                LifecycleReason(
                    code: "changed-files",
                    message: "Only changed SourceUnits were selected."
                )
            ),
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )

        let atomic = try #require(snapshot.atomicObservations.first)
        #expect(atomic.outcome.provesAbsence)
        #expect(snapshot.isAtomicallyComplete)
        #expect(!snapshot.supportsRepositoryAbsence)

        _ = try LifecycleArtifactStore(artifactURL: fixture.url).ingest(snapshot)
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.url).load()
        #expect(persisted.findings.isEmpty)
        #expect(persisted.snapshots.first?.atomicObservations.first?.outcome.provesAbsence == true)
    }

    @Test("AT-7 complete comparable committed absence resolves a Finding")
    func completeComparableAbsenceResolvesFinding() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let observed = try makeObservation(
            id: "observed",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let absent = try makeObservation(
            id: "absent",
            sequence: 2,
            predecessor: "observed",
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )

        _ = try store.ingest(observed)
        _ = try store.ingest(absent)
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.url).load()
        let finding = try #require(persisted.findings.first)
        let lastEvent = try #require(finding.events.last)

        #expect(absent.supportsRepositoryAbsence)
        #expect(finding.lifecycleState == .resolved)
        #expect(finding.evidenceState == .verifiedAbsent)
        guard case .resolved(let evidence) = lastEvent.transition else {
            Issue.record("Expected a resolved event")
            return
        }
        #expect(evidence.priorSnapshotID == observed.id)
        #expect(evidence.coveredAtomicObservationIDs == absent.atomicObservations.map(\.id))
        #expect(evidence.reasons.map(\.code) == ["complete-comparable-absence"])
    }

    @Test("AT-8 parse failure leaves the prior Finding open and unverified")
    func parseFailureCannotResolveFinding() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let observed = try makeObservation(
            id: "before-parse-failure",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let parseFailed = try makeObservation(
            id: "parse-failed",
            sequence: 2,
            predecessor: "before-parse-failure",
            source: "func broken( {",
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )

        _ = try store.ingest(observed)
        _ = try store.ingest(parseFailed)
        let persisted = try store.load()
        let finding = try #require(persisted.findings.first)
        let atomic = try #require(parseFailed.atomicObservations.first)

        #expect(atomic.outcome.kind == .notExecuted)
        #expect(!atomic.outcome.provesAbsence)
        #expect(!parseFailed.isAtomicallyComplete)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .unverified)
        guard case .unverified(let reasons) = finding.events.last?.transition else {
            Issue.record("Expected an unverified event")
            return
        }
        #expect(reasons.map(\.code) == ["atomic-observation-not-executed"])
    }
}
