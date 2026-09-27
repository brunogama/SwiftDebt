import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 explanation supporting Snapshot CLI")
struct LifecycleExplanationSupportingSnapshotCLIWorkflowTests {
    @Test("Text explanation preserves supporting Snapshot evidence from JSON")
    func supportingSnapshotEvidenceMatchesInspection() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let opening = try makeObservation(
            id: "supporting-opening",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let incomplete = try makeObservation(
            id: "supporting-incomplete",
            sequence: 2,
            predecessor: opening.id.rawValue,
            engineVersion: "engine\u{2028}forged",
            rules: [LifecycleRuleV1(mode: .failed)]
        )
        _ = try store.ingest(opening)
        _ = try store.ingest(incomplete)
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
        #expect(report.supportingSnapshots.map(\.id) == [opening.id, incomplete.id])
        for snapshot in report.supportingSnapshots {
            let inspection = try runLifecycleCLI([
                "lifecycle", "snapshot", fixture.url.path, snapshot.id.rawValue,
                "--format", "text",
            ])
            #expect(inspection.status == 0)
            let inspectionLines = inspection.standardOutput.split(separator: "\n").map(String.init)
            let start = try #require(inspectionLines.firstIndex { $0.hasPrefix("Legacy lineage:") })
            let end =
                inspectionLines.firstIndex { $0.hasPrefix("Affected Finding ") }
                ?? inspectionLines.count
            let evidence = inspectionLines[start..<end].joined(separator: "\n")
            #expect(
                text.standardOutput.contains(
                    "Supporting Snapshot \(snapshot.id.rawValue)\n" + evidence + "\n"
                )
            )
            for atomic in snapshot.atomicObservations {
                #expect(text.standardOutput.contains("Atomic Observation \(atomic.id.rawValue)"))
            }
            for detection in snapshot.detections {
                #expect(text.standardOutput.contains("Detection \(detection.id.rawValue)"))
            }
        }
        #expect(text.standardOutput.contains("Engine: engine\\u{2028}forged"))
        #expect(!text.standardOutput.contains("\u{2028}"))
        #expect(try Data(contentsOf: fixture.url) == before)
    }
}
