import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 AT-23 explanation blocker parity CLI")
struct LifecycleExplanationBlockerParityCLIWorkflowTests {
    @Test("Ambiguous explanation ties every unresolved Detection to its Snapshot and candidates")
    func ambiguityPreservesEveryJSONReference() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "parity-opening",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .repeated(2))]
        )
        let ambiguous = try makeObservation(
            id: "parity-ambiguous\u{2028}forged",
            sequence: 2,
            predecessor: original.id.rawValue,
            rules: [LifecycleRuleV1(mode: .repeated(1))]
        )
        _ = try store.ingest(original)
        _ = try store.ingest(ambiguous)
        let findingID = try #require(store.load().findings.first?.id)
        let before = try Data(contentsOf: fixture.url)
        let arguments = ["lifecycle", "explain", fixture.url.path, findingID.rawValue]
        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        #expect(json.status == 0, "\(json.standardError)")
        #expect(text.status == 0, "\(text.standardError)")
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        #expect(report.unresolvedDetections.count == 1)
        #expect(!text.standardOutput.contains("\u{2028}"))
        for unresolved in report.unresolvedDetections {
            let snapshotID = unresolved.snapshotID.rawValue.replacingOccurrences(of: "\u{2028}", with: "\\u{2028}")
            let detectionID = unresolved.detectionID.rawValue.replacingOccurrences(of: "\u{2028}", with: "\\u{2028}")
            let candidates = unresolved.candidateFindingIDs.map(\.rawValue).joined(separator: ", ")
            let reasons = unresolved.reasons.map { "  \($0.code): \($0.message)" }.joined(separator: "\n")
            let expected =
                "Unresolved Detection \(snapshotID) \(detectionID)\n"
                + "  Candidate Findings: \(candidates)\n" + reasons + "\n"
            #expect(text.standardOutput.contains(expected))
        }
        let event = try #require(report.projections.first?.finding.events.last)
        guard case .continuityAmbiguous(let evidence) = event.transition else {
            Issue.record("Expected a persisted continuity ambiguity")
            return
        }
        for candidate in evidence.candidateFindingIDs {
            #expect(text.standardOutput.contains(candidate.rawValue))
        }
        for reason in evidence.reasons {
            #expect(text.standardOutput.contains("  \(reason.code): \(reason.message)"))
        }
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test("Explanation names every unresolved Detection in a one-to-many ambiguity")
    func multipleUnresolvedDetectionsKeepTheirSnapshots() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let opening = try makeObservation(
            id: "parity-split-opening",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .repeated(1))]
        )
        let split = try makeObservation(
            id: "parity-split-current",
            sequence: 2,
            predecessor: opening.id.rawValue,
            rules: [LifecycleRuleV1(mode: .repeated(2))]
        )
        _ = try store.ingest(opening)
        _ = try store.ingest(split)
        let findingID = try #require(store.load().findings.first?.id)
        let arguments = ["lifecycle", "explain", fixture.url.path, findingID.rawValue]
        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        #expect(json.status == 0, "\(json.standardError)")
        #expect(text.status == 0, "\(text.standardError)")
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        #expect(report.unresolvedDetections.count == 2)
        for unresolved in report.unresolvedDetections {
            let candidates = unresolved.candidateFindingIDs.map(\.rawValue).joined(separator: ", ")
            let reasons = unresolved.reasons.map { "  \($0.code): \($0.message)" }.joined(separator: "\n")
            let expected =
                "Unresolved Detection \(unresolved.snapshotID.rawValue) "
                + "\(unresolved.detectionID.rawValue)\n"
                + "  Candidate Findings: \(candidates)\n" + reasons + "\n"
            #expect(text.standardOutput.contains(expected))
        }
    }

    @Test("Unverified explanation retains every persisted blocker")
    func unverifiedPreservesEveryJSONBlocker() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let opening = try makeObservation(
            id: "parity-unverified-opening",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let incomparable = try makeObservation(
            id: "parity-unverified-incomparable",
            sequence: 2,
            predecessor: opening.id.rawValue,
            rules: [LifecycleRuleV2(mode: .committed(1))]
        )
        _ = try store.ingest(opening)
        _ = try store.ingest(incomparable)
        let findingID = try #require(store.load().findings.first?.id)
        let before = try Data(contentsOf: fixture.url)
        let arguments = ["lifecycle", "explain", fixture.url.path, findingID.rawValue]
        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        #expect(json.status == 0, "\(json.standardError)")
        #expect(text.status == 0, "\(text.standardError)")
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        let event = try #require(report.projections.first?.finding.events.last)
        guard case .unverified(let blockers) = event.transition else {
            Issue.record("Expected a persisted unverified transition")
            return
        }
        #expect(!blockers.isEmpty)
        let basis = event.basisEventIDs.map(\.rawValue).joined(separator: ", ")
        let reasons = blockers.map { "  \($0.code): \($0.message)" }.joined(separator: "\n")
        let expected =
            "Event \(event.id.rawValue) snapshot=\(event.snapshotID.rawValue) "
            + "unverified contract=\(event.evidenceContract.rawValue)\n"
            + "  Basis Events: \(basis.isEmpty ? "none" : basis)\n"
            + reasons + "\n"
        #expect(text.standardOutput.contains(expected))
        #expect(try Data(contentsOf: fixture.url) == before)
    }
}
