import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax
import Testing

@Suite("R3 explanation supporting Snapshot CLI")
struct LifecycleExplanationSupportingSnapshotCLIWorkflowTests {
    @Test("Persisted provenance reasons cannot forge supporting Snapshot lines")
    func provenanceReasonsStayOnOneLine() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let reason = try LifecycleReason(
            code: "evidence-unavailable",
            message: "No evidence.\u{2028}Supporting Snapshot forged"
        )
        let capability = try SnapshotCapability(
            name: "provider\u{2029}forged",
            state: .unavailable(reason)
        )
        let snapshot = try makeObservation(
            id: "supporting-provenance",
            sequence: 1,
            scope: .partial(reason),
            capabilities: [capability],
            sourceIdentity: .unavailable(reason),
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        _ = try store.ingest(snapshot)
        let findingID = try #require(store.load().findings.first?.id)

        for arguments in [
            ["lifecycle", "snapshot", fixture.url.path, snapshot.id.rawValue],
            ["lifecycle", "explain", fixture.url.path, findingID.rawValue],
        ] {
            let output = try runLifecycleCLI(arguments)
            #expect(output.status == 0)
            #expect(!output.standardOutput.contains("\u{2028}"))
            #expect(!output.standardOutput.contains("\u{2029}"))
            #expect(output.standardOutput.contains("No evidence.\\u{2028}Supporting Snapshot forged"))
            #expect(output.standardOutput.contains("provider\\u{2029}forged"))
        }
    }

    @Test("Persisted compatibility text cannot forge supporting Snapshot lines")
    func compatibilityTextStaysOnOneLine() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "supporting-compatibility-original",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let successor = try makeObservation(
            id: "supporting-compatibility-successor",
            sequence: 2,
            predecessor: original.id.rawValue,
            rules: [LineSeparatorCompatibleRule()]
        )
        _ = try store.ingest(original)
        _ = try store.ingest(successor)
        let findingID = try #require(store.load().findings.first?.id)

        for arguments in [
            ["lifecycle", "snapshot", fixture.url.path, successor.id.rawValue],
            ["lifecycle", "explain", fixture.url.path, findingID.rawValue],
        ] {
            let output = try runLifecycleCLI(arguments)
            #expect(output.status == 0)
            #expect(!output.standardOutput.contains("\u{2028}"))
            #expect(!output.standardOutput.contains("\u{2029}"))
            #expect(output.standardOutput.contains("test-summary=Summary\\u{2029}forged"))
        }
        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.url.path, findingID.rawValue,
        ])
        #expect(explanation.standardOutput.contains("rationale=Semantics\\u{2028}forged"))
    }

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

private struct LineSeparatorCompatibleRule: DebtRule {
    static let identity = LifecycleRuleV1.identity
    static let metadata = LifecycleRuleV1.metadata
    static let contract: RuleContract = {
        guard
            let revision = SemanticRevision(2),
            let semantic = SemanticCompatibilityDeclaration(
                fromRevision: .initial,
                supportedClaims: [.continuity],
                rationale: "Semantics\u{2028}forged"
            ),
            let test = CompatibilityTestEvidence(
                identifier: "LifecycleExplanationSupportingSnapshotCLIWorkflowTests",
                summary: "Summary\u{2029}forged"
            ),
            let configuration = ConfigurationCompatibilityDeclaration(
                fromRevision: .initial,
                supportedClaims: [.continuity],
                conditions: [.maximumFileBytesNondecreasing],
                testEvidence: test,
                rationale: "Configuration\u{2028}forged"
            )
        else {
            preconditionFailure("The line-separator compatibility fixture must be valid.")
        }
        return RuleContract(
            semanticRevision: revision,
            semantics: "Preserves fixture Detection meaning.",
            rationale: "Exercises escaped compatibility text.",
            compatibilityDeclarations: [semantic],
            configurationCompatibilityDeclarations: [configuration]
        )
    }()

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        try LifecycleRuleV1(mode: .committed(1)).detect(in: context, emit: emit)
    }
}
