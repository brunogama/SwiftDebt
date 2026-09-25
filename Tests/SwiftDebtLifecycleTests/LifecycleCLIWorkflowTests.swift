import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 read-only CLI acceptance")
struct LifecycleCLIWorkflowTests {
    @Test("Lifecycle CLI rejects duplicate format options")
    func duplicateFormatFails() throws {
        let result = try runLifecycleCLI([
            "lifecycle", "inventory", "missing.json", "--format", "text", "--format=json",
        ])
        #expect(result.status == 2)
        #expect(result.standardError.contains("Duplicate option: --format"))
    }

    @Test("Persisted lifecycle artifact supports inventory, explanation, and snapshot inspection")
    func readOnlyCommandsInspectPersistedEvidence() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "cli-original",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .repeated(1))]
        )
        let ambiguous = try makeObservation(
            id: "cli-ambiguous",
            sequence: 2,
            predecessor: "cli-original",
            rules: [LifecycleRuleV1(mode: .repeated(2))]
        )
        _ = try store.ingest(original)
        _ = try store.ingest(ambiguous)
        let findingID = try #require(store.load().findings.first?.id)
        let bytesBefore = try Data(contentsOf: fixture.url)

        let inventory = try runLifecycleCLI([
            "lifecycle", "inventory", fixture.url.path, "--format", "json",
        ])
        #expect(inventory.status == 0)
        #expect(inventory.standardError.isEmpty)
        let inventoryReport = try JSONDecoder().decode(
            LifecycleInventoryReport.self,
            from: Data(inventory.standardOutput.utf8)
        )
        #expect(inventoryReport.reportKind == "swiftdebt-lifecycle-inventory")
        #expect(inventoryReport.findings.first?.evidenceState == .continuityAmbiguous)
        #expect(inventoryReport.unresolvedDetections.count == 2)

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.url.path, findingID.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("structural-assignment-not-unique"))
        #expect(explanation.standardOutput.contains("more than one predecessor or successor"))

        let inspection = try runLifecycleCLI([
            "lifecycle", "snapshot", fixture.url.path, ambiguous.id.rawValue,
        ])
        #expect(inspection.status == 0)
        #expect(inspection.standardOutput.contains("Snapshot cli-ambiguous"))
        #expect(inspection.standardOutput.contains("Atomic observations complete: true"))
        #expect(try Data(contentsOf: fixture.url) == bytesBefore)
    }

    @Test("AT-23 text and JSON explanations preserve every ambiguity candidate and blocker")
    func explanationFormatsPreserveAmbiguityEvidence() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let originals = try makeObservation(
            id: "cli-parity-originals",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .repeated(2))]
        )
        let collapsed = try makeObservation(
            id: "cli-parity-collapsed",
            sequence: 2,
            predecessor: originals.id.rawValue,
            rules: [LifecycleRuleV1(mode: .repeated(1))]
        )
        _ = try store.ingest(originals)
        _ = try store.ingest(collapsed)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)
        let expected = try #require(artifact.unresolvedDetections.first)
        #expect(expected.candidateFindingIDs == artifact.findings.map(\.id))

        let text = try explanation(finding.id, artifact: fixture.url, format: .text)
        let json = try explanation(finding.id, artifact: fixture.url, format: .json)
        #expect(text.status == 0)
        #expect(json.status == 0)
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        #expect(report.unresolvedDetections == [expected])
        #expect(
            text.standardOutput.contains(
                "Candidate Findings: "
                    + expected.candidateFindingIDs.map(\.rawValue).joined(separator: ", ")
            )
        )
        for candidate in expected.candidateFindingIDs {
            #expect(text.standardOutput.contains(candidate.rawValue))
        }
        for reason in expected.reasons {
            #expect(text.standardOutput.contains("\(reason.code): \(reason.message)"))
        }
    }

    @Test("AT-23 text and JSON explanations preserve unverified blockers")
    func explanationFormatsPreserveUnverifiedReasons() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let first = try makeObservation(
            id: "cli-unverified-v1",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let incomparable = try makeObservation(
            id: "cli-unverified-v2",
            sequence: 2,
            predecessor: first.id.rawValue,
            rules: [LifecycleRuleV2(mode: .committed(1))]
        )
        _ = try store.ingest(first)
        _ = try store.ingest(incomparable)
        let artifact = try store.load()
        let finding = try #require(artifact.findings.first)
        guard case .unverified(let expectedReasons) = finding.events.last?.transition else {
            Issue.record("Expected the Semantic Revision boundary to remain unverified")
            return
        }

        let text = try explanation(finding.id, artifact: fixture.url, format: .text)
        let json = try explanation(finding.id, artifact: fixture.url, format: .json)
        #expect(text.status == 0)
        #expect(json.status == 0)
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        guard case .unverified(let jsonReasons) = report.finding.events.last?.transition else {
            Issue.record("Expected JSON to preserve the unverified transition")
            return
        }
        #expect(jsonReasons == expectedReasons)
        for reason in expectedReasons {
            #expect(text.standardOutput.contains("\(reason.code): \(reason.message)"))
        }
    }

    @Test("Read-only CLI rejects an unknown lifecycle schema")
    func cliFailsClosedForUnknownSchema() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "cli-schema",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        _ = try store.ingest(snapshot)
        var root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture.url)) as? [String: Any]
        )
        root["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: root).write(to: fixture.url, options: .atomic)

        let result = try runLifecycleCLI(["lifecycle", "inventory", fixture.url.path])

        #expect(result.status == 2)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("Unsupported lifecycle artifact schema version 99"))
    }

    private func explanation(
        _ findingID: FindingID,
        artifact: URL,
        format: LifecycleReadFormat
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "lifecycle", "explain", artifact.path, findingID.rawValue,
            "--format", format.rawValue,
        ])
    }
}
