import Foundation
import SwiftDebtLifecycle
import SwiftDebtSyntax
import Testing

@Suite("R3 snapshot audit text CLI")
struct LifecycleSnapshotAuditTextCLIWorkflowTests {
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
