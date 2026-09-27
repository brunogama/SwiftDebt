import Foundation
import Testing
@testable import SwiftDebtLifecycle

@Suite("R3 explanation event evidence text CLI")
struct LifecycleExplanationEvidenceTextCLIWorkflowTests {
    @Test("Explanation text names event identity, basis, contract, and observation references")
    func observedAndResolvedEventEvidenceMatchesJSON() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "event-audit-original",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let observed = try makeObservation(
            id: "event-audit-observed",
            sequence: 2,
            predecessor: original.id.rawValue,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let resolved = try makeObservation(
            id: "event-audit-resolved",
            sequence: 3,
            predecessor: observed.id.rawValue,
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        _ = try store.ingest(original)
        _ = try store.ingest(observed)
        _ = try store.ingest(resolved)
        let findingID = try #require(store.load().findings.first?.id)
        let before = try Data(contentsOf: fixture.url)
        let arguments = ["lifecycle", "explain", fixture.url.path, findingID.rawValue]

        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])

        #expect(json.status == 0)
        #expect(text.status == 0)
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        let events = try #require(report.projections.first?.finding.events)
        #expect(events.map(\.transition.kind) == [.opened, .observed, .resolved])
        for event in events {
            #expect(
                text.standardOutput.contains(
                    "Event \(event.id.rawValue) snapshot=\(event.snapshotID.rawValue) "
                        + "\(event.transition.kind.rawValue) contract=\(event.evidenceContract.rawValue)"
                )
            )
            let basis = event.basisEventIDs.map(\.rawValue).joined(separator: ", ")
            #expect(text.standardOutput.contains("  Basis Events: \(basis.isEmpty ? "none" : basis)"))
            switch event.transition {
            case .opened(let evidence):
                #expect(
                    text.standardOutput.contains(
                        "  Detection: \(evidence.detectionID.rawValue) "
                            + "atomic=\(evidence.atomicObservationID.rawValue)"
                    )
                )
            case .observed(let evidence), .reopened(let evidence):
                #expect(
                    text.standardOutput.contains(
                        "  Current Detection: \(evidence.currentDetection.detectionID.rawValue) "
                            + "atomic=\(evidence.currentDetection.atomicObservationID.rawValue)"
                    )
                )
                #expect(
                    text.standardOutput.contains(
                        "  Prior Detection: \(evidence.priorSnapshotID.rawValue) "
                            + evidence.priorDetectionID.rawValue
                    )
                )
            case .resolved(let evidence):
                #expect(text.standardOutput.contains("  Prior Snapshot: \(evidence.priorSnapshotID.rawValue)"))
                let covered = evidence.coveredAtomicObservationIDs.map(\.rawValue).joined(separator: ", ")
                #expect(text.standardOutput.contains("  Covered Atomic Observations: \(covered)"))
            case .unverified, .continuityAmbiguous:
                Issue.record("The fixture should produce only opened, observed, and resolved events")
            }
        }
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test("Explanation text names ambiguous Detection and Finding references")
    func ambiguousEventReferencesMatchJSON() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "event-audit-ambiguous-original",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .repeated(2))]
        )
        let collapsed = try makeObservation(
            id: "event-audit-ambiguous-collapsed",
            sequence: 2,
            predecessor: original.id.rawValue,
            rules: [LifecycleRuleV1(mode: .repeated(1))]
        )
        _ = try store.ingest(original)
        _ = try store.ingest(collapsed)
        let findingID = try #require(store.load().findings.first?.id)
        let arguments = ["lifecycle", "explain", fixture.url.path, findingID.rawValue]

        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])

        #expect(json.status == 0)
        #expect(text.status == 0)
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        let event = try #require(report.projections.first?.finding.events.last)
        guard case .continuityAmbiguous(let evidence) = event.transition else {
            Issue.record("Expected an ambiguous event")
            return
        }
        #expect(text.standardOutput.contains("Event \(event.id.rawValue)"))
        #expect(
            text.standardOutput.contains(
                "  Current Detection IDs: \(evidence.currentDetectionIDs.map(\.rawValue).joined(separator: ", "))"
            )
        )
        #expect(
            text.standardOutput.contains(
                "  Candidate Findings: \(evidence.candidateFindingIDs.map(\.rawValue).joined(separator: ", "))"
            )
        )
    }

    @Test("Event audit fields escape Unicode line separators")
    func eventTextCannotForgeLines() throws {
        let event = LifecycleEvent(
            id: try LifecycleEventID("event\u{2028}forged"),
            snapshotID: try SnapshotID("snapshot\u{2028}forged"),
            basisEventIDs: [try LifecycleEventID("basis\u{2028}forged")],
            transition: .unverified([
                try LifecycleReason(
                    code: "unsupported\u{2028}forged",
                    message: "No evidence.\u{2028}Event forged"
                )
            ])
        )

        let lines = LifecycleReadService().renderEvent(event)

        #expect(lines.count == 3)
        #expect(lines.allSatisfy { !$0.contains("\u{2028}") })
        #expect(lines[0].contains("event\\u{2028}forged snapshot=snapshot\\u{2028}forged"))
        #expect(lines[1].contains("basis\\u{2028}forged"))
        #expect(lines[2].contains("unsupported\\u{2028}forged: No evidence.\\u{2028}"))
    }
}
