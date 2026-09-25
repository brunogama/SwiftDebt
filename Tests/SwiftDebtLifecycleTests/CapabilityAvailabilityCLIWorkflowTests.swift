import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 capability availability CLI acceptance")
struct CapabilityAvailabilityCLIWorkflowTests {
    @Test("AT-26 omitted and unavailable capabilities name the blocker in both explanation formats")
    func unavailableCapabilityRemainsUnverifiedAndExplained() throws {
        let available = try SnapshotCapability(name: "compiler-evidence", state: .available)
        let failure = try LifecycleReason(
            code: "provider-start-failed",
            message: "The compiler evidence provider could not start."
        )
        let unavailable = try SnapshotCapability(
            name: "compiler-evidence",
            state: .unavailable(failure)
        )

        for (label, capabilities, expectedDetail) in [
            ("omitted", [SnapshotCapability](), "compiler-evidence"),
            ("unavailable", [unavailable], "provider-start-failed"),
        ] {
            let fixture = try TemporaryLifecycleArtifact()
            let store = LifecycleArtifactStore(artifactURL: fixture.url)
            let first = try makeObservation(
                id: "at26-\(label)-root",
                sequence: 1,
                capabilities: [available],
                rules: [LifecycleRuleV1(mode: .committed(1))]
            )
            let later = try makeObservation(
                id: "at26-\(label)-child",
                sequence: 2,
                predecessor: first.id.rawValue,
                capabilities: capabilities,
                rules: [LifecycleRuleV1(mode: .committed(0))]
            )
            _ = try store.ingest(first)
            _ = try store.ingest(later)

            let finding = try #require(store.load().findings.first)
            #expect(finding.lifecycleState == .open)
            guard case .unverified(let reasons) = finding.events.last?.transition else {
                Issue.record("Expected unavailable capability to block resolution")
                return
            }
            #expect(reasons.contains { $0.message.contains("compiler-evidence") })
            #expect(reasons.contains { $0.message.contains(expectedDetail) })

            let arguments = ["lifecycle", "explain", fixture.url.path, finding.id.rawValue]
            let text = try runLifecycleCLI(arguments + ["--format", "text"])
            let json = try runLifecycleCLI(arguments + ["--format", "json"])
            #expect(text.status == 0)
            #expect(json.status == 0)
            let report = try JSONDecoder().decode(
                FindingExplanationReport.self,
                from: Data(json.standardOutput.utf8)
            )
            guard case .unverified(let jsonReasons) = report.finding.events.last?.transition else {
                Issue.record("Expected JSON explanation to retain the unverified transition")
                return
            }
            #expect(jsonReasons == reasons)
            for reason in reasons {
                #expect(text.standardOutput.contains("\(reason.code): \(reason.message)"))
            }
        }
    }
}
