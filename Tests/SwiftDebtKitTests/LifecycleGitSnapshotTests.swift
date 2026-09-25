import Foundation
import Testing

@testable import SwiftDebtKit

@Suite("Lifecycle Git capture failures")
struct LifecycleGitSnapshotTests {
    @Test("A transient Git failure cannot become a content-only snapshot")
    func transientFailureFailsClosed() throws {
        let runner = RecordingGitRunner()
        runner.enqueue(
            GitHistoryProcessResult(
                exitCode: -1, stdout: "", stderr: "Git unavailable", timedOut: false
            )
        )

        do {
            _ = try LifecycleGitSnapshotProvider(runner: runner).capture(
                root: FileManager.default.temporaryDirectory,
                excludingGeneratedOutputs: []
            )
            Issue.record("Expected transient Git inspection to fail")
        } catch let error as LifecycleAnalysisError {
            #expect(error == .gitInspectionFailed("Git unavailable"))
        }
    }

    @Test("A confirmed non-Git directory remains explicitly unavailable")
    func nonRepositoryIsUnavailable() throws {
        let runner = RecordingGitRunner()
        runner.enqueue(
            GitHistoryProcessResult(
                exitCode: 128, stdout: "", stderr: "fatal: not a git repository", timedOut: false
            )
        )

        let result = try LifecycleGitSnapshotProvider(runner: runner).capture(
            root: FileManager.default.temporaryDirectory,
            excludingGeneratedOutputs: []
        )
        #expect(result == .unavailable)
    }
}
