import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 inventory text parity CLI")
struct LifecycleInventoryTextParityCLIWorkflowTests {
    @Test("Inventory text names projection fields and full unresolved reasons from JSON")
    func inventorySummaryPreservesFields() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let opening = try makeObservation(
            id: "inventory-opening",
            lineage: "inventory\u{2028}forged",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .repeated(2))]
        )
        let collapsed = try makeObservation(
            id: "inventory-collapsed",
            lineage: "inventory\u{2028}forged",
            sequence: 2,
            predecessor: opening.id.rawValue,
            rules: [LifecycleRuleV1(mode: .repeated(1))]
        )
        _ = try store.ingest(opening)
        _ = try store.ingest(collapsed)
        let before = try Data(contentsOf: fixture.url)
        let arguments = ["lifecycle", "inventory", fixture.url.path]
        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        #expect(json.status == 0, "\(json.standardError)")
        #expect(text.status == 0, "\(text.standardError)")
        let report = try JSONDecoder().decode(
            LifecycleInventoryReport.self,
            from: Data(json.standardOutput.utf8)
        )
        #expect(report.findings.count == 2)
        #expect(report.unresolvedDetections.count == 1)
        #expect(
            text.standardOutput.contains(
                "SwiftDebt lifecycle inventory schema=\(report.schemaVersion) kind=\(report.reportKind)"
            )
        )
        #expect(!text.standardOutput.contains("\u{2028}"))
        for finding in report.findings {
            #expect(text.standardOutput.contains(finding.id.rawValue))
            #expect(text.standardOutput.contains("Lineage: inventory\\u{2028}forged"))
            #expect(
                text.standardOutput.contains(
                    "Semantic revision: \(finding.rule.semanticRevision.rawValue)"
                )
            )
            #expect(text.standardOutput.contains("Full evidence: swift-debt lifecycle explain ARTIFACT FINDING_ID"))
        }
        for unresolved in report.unresolvedDetections {
            for reason in unresolved.reasons {
                #expect(text.standardOutput.contains("  Reason: \(reason.code): \(reason.message)"))
            }
        }
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test("Inventory text retains Introduction Conclusion summary and points to full history")
    func introductionSummaryPreservesDecision() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: "func broken( {\n", message: "add unparseable source")
        _ = try fixture.commit(
            source: "func load() throws -> Int { 1 }\nfunc run() { _ = try! load() }\n",
            message: "repair with forced try"
        )
        #expect(try analyzeLifecycle(fixture).status == 0)
        let finding = try #require(LifecycleArtifactStore(artifactURL: fixture.artifact).load().findings.first)
        let inference = try runLifecycleCLI([
            "lifecycle", "infer-introduction", fixture.artifact.path, finding.id.rawValue,
            "--repository", fixture.repository.path, "--max-revisions", "8",
        ])
        #expect(inference.status == 0, "\(inference.standardError)")
        let arguments = ["lifecycle", "inventory", fixture.artifact.path]
        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        #expect(json.status == 0, "\(json.standardError)")
        #expect(text.status == 0, "\(text.standardError)")
        let report = try JSONDecoder().decode(
            LifecycleInventoryReport.self,
            from: Data(json.standardOutput.utf8)
        )
        let conclusion = try #require(report.findings.first?.introductionConclusion)
        #expect(conclusion.kind == .bounded)
        #expect(
            text.standardOutput.contains(
                "Introduction attempt: \(conclusion.attempt) contract=\(conclusion.evidenceContract.rawValue)"
            )
        )
        for reason in conclusion.reasons {
            #expect(text.standardOutput.contains("  Introduction reason: \(reason.code): \(reason.message)"))
        }
        #expect(text.standardOutput.contains("Full evidence: swift-debt lifecycle explain ARTIFACT FINDING_ID"))
    }
}
