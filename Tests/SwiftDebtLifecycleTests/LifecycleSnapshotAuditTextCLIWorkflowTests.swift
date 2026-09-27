import Foundation
import SwiftDebtSyntax
import Testing
@testable import SwiftDebtLifecycle

@Suite("R3 snapshot audit text CLI")
struct LifecycleSnapshotAuditTextCLIWorkflowTests {
    @Test("Snapshot text preserves affected Findings and every unresolved Detection in JSON")
    func snapshotTextPreservesDownstreamEffects() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let original = try makeObservation(
            id: "snapshot-effects-original",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .repeated(2))]
        )
        let collapsed = try makeObservation(
            id: "snapshot-effects-collapsed",
            sequence: 2,
            predecessor: original.id.rawValue,
            rules: [LifecycleRuleV1(mode: .repeated(1))]
        )
        _ = try store.ingest(original)
        _ = try store.ingest(collapsed)
        let before = try Data(contentsOf: fixture.url)
        let arguments = ["lifecycle", "snapshot", fixture.url.path, collapsed.id.rawValue]

        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        let text = try runLifecycleCLI(arguments + ["--format", "text"])

        #expect(json.status == 0)
        #expect(text.status == 0)
        let report = try JSONDecoder().decode(
            SnapshotInspectionReport.self,
            from: Data(json.standardOutput.utf8)
        )
        #expect(report.affectedFindingIDs.count == 2)
        #expect(report.unresolvedDetections.count == 1)
        for findingID in report.affectedFindingIDs {
            #expect(text.standardOutput.contains("Affected Finding \(findingID.rawValue)"))
        }
        for unresolved in report.unresolvedDetections {
            #expect(
                text.standardOutput.contains(
                    "Unresolved Detection \(unresolved.snapshotID.rawValue) \(unresolved.detectionID.rawValue)"
                )
            )
            #expect(
                text.standardOutput.contains(
                    "  Candidate Findings: "
                        + unresolved.candidateFindingIDs.map(\.rawValue).joined(separator: ", ")
                )
            )
            for reason in unresolved.reasons {
                #expect(text.standardOutput.contains("\(reason.code): \(reason.message)"))
            }
        }
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test("Unresolved text escapes line separators in new audit fields")
    func unresolvedTextCannotForgeAuditLines() throws {
        let unresolved = UnresolvedDetection(
            snapshotID: try SnapshotID("snapshot\u{2028}injected"),
            detectionID: try DetectionID("detection\u{2028}injected"),
            candidateFindingIDs: [try FindingID("finding\u{2028}injected")],
            reasons: [
                try LifecycleReason(
                    code: "ambiguous\u{2028}injected",
                    message: "Needs review.\u{2028}Unresolved Detection forged"
                )
            ]
        )

        let lines = LifecycleReadService().renderUnresolvedDetection(unresolved)
        let affected = LifecycleReadService().renderAffectedFinding(
            try FindingID("finding\u{2028}injected")
        )

        #expect(lines.count == 3)
        #expect(lines.allSatisfy { !$0.contains("\u{2028}") })
        #expect(affected == "Affected Finding finding\\u{2028}injected")
        #expect(lines[0].contains("snapshot\\u{2028}injected detection\\u{2028}injected"))
        #expect(lines[1].contains("finding\\u{2028}injected"))
        #expect(lines[2].contains("ambiguous\\u{2028}injected: Needs review.\\u{2028}"))
    }

    @Test("Text snapshot inspection keeps a diagnostic filename on one evidence line")
    func newlineInDiagnosticFilenameCannotForgeEvidence() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: "func run() {}\n", message: "add source")
        let arguments = [
            "analyze", fixture.repository.path, "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
        ]
        #expect(try runLifecycleCLI(arguments).status == 0)
        _ = try fixture.commit(source: "func broken( {\n", message: "break parser")
        #expect(try runLifecycleCLI(arguments).status == 2)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let snapshot = try #require(artifact.snapshots.last)
        let source = try #require(snapshot.sources.first)
        guard case .failed(let diagnostics) = source.parseOutcome else {
            Issue.record("Expected persisted parse diagnostics")
            return
        }
        let originalFile = try #require(diagnostics.first).location.file
        let injectedFile = originalFile + "\nAtomic Observation forged"
        var artifactJSON = try artifactJSONObject(at: fixture.artifact)
        var snapshots = try #require(artifactJSON["snapshots"] as? [[String: Any]])
        var lastSnapshot = try #require(snapshots.last)
        snapshots.removeLast()
        var sources = try #require(lastSnapshot["sources"] as? [[String: Any]])
        var firstSource = try #require(sources.first)
        var parseOutcome = try #require(firstSource["parseOutcome"] as? [String: Any])
        var recordedDiagnostics = try #require(parseOutcome["diagnostics"] as? [[String: Any]])
        for index in recordedDiagnostics.indices {
            var location = try #require(recordedDiagnostics[index]["location"] as? [String: Any])
            location["file"] = injectedFile
            recordedDiagnostics[index]["location"] = location
        }
        parseOutcome["diagnostics"] = recordedDiagnostics
        firstSource["parseOutcome"] = parseOutcome
        sources[0] = firstSource
        lastSnapshot["sources"] = sources
        snapshots.append(lastSnapshot)
        artifactJSON["snapshots"] = snapshots
        try lifecycleJSONData(artifactJSON).write(to: fixture.artifact)

        let result = try runLifecycleCLI([
            "lifecycle", "snapshot", fixture.artifact.path, snapshot.id.rawValue,
        ])

        #expect(result.status == 0)
        #expect(result.standardOutput.contains("\(originalFile)\\nAtomic Observation forged"))
        #expect(!result.standardOutput.contains("\nAtomic Observation forged"))
    }

    @Test("Text snapshot inspection names parse failure and the not-executed rule")
    func parseFailureIsVisible() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(
            source: "func load() throws -> Int { 1 }\nfunc run() { _ = try! load() }\n",
            message: "add forced try"
        )
        let analysisArguments = [
            "analyze", fixture.repository.path, "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
        ]
        #expect(try runLifecycleCLI(analysisArguments).status == 0)
        _ = try fixture.commit(source: "func load( {\n", message: "break parser")
        #expect(try runLifecycleCLI(analysisArguments).status == 2)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let snapshot = try #require(artifact.snapshots.last)
        let source = try #require(snapshot.sources.first)
        guard case .failed(let diagnostics) = source.parseOutcome else {
            Issue.record("Expected a persisted parse failure")
            return
        }
        let atomic = try #require(snapshot.atomicObservations.first)
        guard case .notExecuted(let reason) = atomic.outcome else {
            Issue.record("Expected a not-executed Atomic Observation")
            return
        }

        let result = try runLifecycleCLI([
            "lifecycle", "snapshot", fixture.artifact.path, snapshot.id.rawValue,
        ])

        #expect(result.status == 0)
        #expect(result.standardOutput.contains("SourceUnit \(source.sourcePath.rawValue): parse-failed"))
        #expect(result.standardOutput.contains("Atomic Observation \(atomic.id.rawValue)"))
        #expect(result.standardOutput.contains("\(reason.code): \(reason.message)"))
        for diagnostic in diagnostics {
            #expect(
                result.standardOutput.contains(
                    "\(diagnostic.location.file):\(diagnostic.location.line):\(diagnostic.location.column)"
                )
            )
            #expect(result.standardOutput.contains(diagnostic.message))
        }
    }

    @Test("Text snapshot inspection exposes the same incomplete observation and detection evidence as JSON")
    func textAndJSONPreserveObservationEvidence() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let snapshot = try makeObservation(
            id: "snapshot-audit-text",
            sequence: 1,
            source: "func load() throws -> Int { 1 }\nfunc run() { _ = try! load() }\n",
            rules: [LifecycleRuleV1(mode: .failed), ForceTryRule()]
        )
        _ = try store.ingest(snapshot)
        let arguments = ["lifecycle", "snapshot", fixture.url.path, snapshot.id.rawValue]

        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        let json = try runLifecycleCLI(arguments + ["--format", "json"])

        #expect(text.status == 0)
        #expect(json.status == 0)
        let report = try JSONDecoder().decode(
            SnapshotInspectionReport.self,
            from: Data(json.standardOutput.utf8)
        )
        #expect(report.snapshot == snapshot)
        for source in report.snapshot.sources {
            #expect(text.standardOutput.contains("SourceUnit \(source.sourcePath.rawValue): parsed"))
        }
        for atomic in report.snapshot.atomicObservations {
            #expect(text.standardOutput.contains("Atomic Observation \(atomic.id.rawValue)"))
            switch atomic.outcome {
            case .committed(let ids):
                for id in ids {
                    #expect(text.standardOutput.contains("Detection \(id.rawValue)"))
                }
            case .unsupported(let reason), .failed(let reason), .excluded(let reason), .notExecuted(let reason):
                #expect(text.standardOutput.contains("\(reason.code): \(reason.message)"))
            }
        }
        for detection in report.snapshot.detections {
            #expect(text.standardOutput.contains("Detection \(detection.id.rawValue)"))
            #expect(text.standardOutput.contains(detection.message))
            #expect(text.standardOutput.contains(detection.location.sourcePath.rawValue))
        }
    }
}
