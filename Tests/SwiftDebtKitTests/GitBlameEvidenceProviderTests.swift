import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import Testing

@testable import SwiftDebtKit

@Suite("Git blame evidence provider")
struct GitBlameEvidenceProviderTests {
    @Test("Malformed blame output is unavailable and never becomes line facts")
    func malformedOutputFailsClosed() throws {
        let fixture = try ProviderFixture()
        let runner = RecordingGitRunner()
        runner.enqueue(.success(fixture.head.rawValue + "\n"))
        runner.enqueue(.success(""))
        runner.enqueue(.success(fixture.source.content))
        runner.enqueue(
            .success(
                "\(fixture.head.rawValue) 1 1\n"
                    + "filename Sources/Input.swift\n"
                    + "\tnot the captured source\n"
            )
        )

        let result = GitBlameEvidenceProvider(runner: runner).inspect(
            executablePath: "/usr/bin/git",
            capture: fixture.capture,
            sources: [fixture.source]
        )

        guard case .unavailable(let reason) = result else {
            Issue.record("Expected malformed provider output to be unavailable")
            return
        }
        #expect(reason.code == "git-blame-output-malformed")
        #expect(runner.calls.allSatisfy { $0.executableURL.path == "/usr/bin/git" })
        #expect(runner.calls.allSatisfy { $0.arguments.first == "-C" })
        let blameCall = try #require(runner.calls.first { $0.arguments.contains("blame") })
        #expect(blameCall.arguments.contains("--no-ignore-revs-file"))
    }

    @Test("Committed source bytes must match the analyzed SourceUnit")
    func sourceMismatchFailsClosed() throws {
        let fixture = try ProviderFixture()
        let runner = RecordingGitRunner()
        runner.enqueue(.success(fixture.head.rawValue + "\n"))
        runner.enqueue(.success(""))
        runner.enqueue(.success("func changedAfterCapture() {}\n"))

        let result = GitBlameEvidenceProvider(runner: runner).inspect(
            executablePath: "/usr/bin/git",
            capture: fixture.capture,
            sources: [fixture.source]
        )

        guard case .unavailable(let reason) = result else {
            Issue.record("Expected mismatched source bytes to be unavailable")
            return
        }
        #expect(reason.code == "git-blame-source-mismatch")
        #expect(runner.calls.count == 3)
    }
}

private final class ProviderFixture {
    let directory: URL
    let source: SourceUnit
    let head: GitRevisionID
    let capture: LifecycleAnalysisCapture

    init() throws {
        directory = try temporaryGitTestDirectory()
        try writeGitFixture("func run() { _ = try! load() }\n", name: "Sources/Input.swift", root: directory)
        let discovery = SourceDiscovery()
        let request = AnalysisRequest(path: directory.path)
        let selection = try discovery.select(request: request, root: directory, excludes: [])
        source = try #require(discovery.read(selection, maximumFileBytes: 1_024).first)
        head = try GitRevisionID(String(repeating: "a", count: 40))
        let snapshot = LifecycleGitSnapshot.available(
            repositoryRoot: directory.path,
            revision: head,
            workingTreeState: .clean,
            parentRevisions: [],
            statusDigest: String(repeating: "0", count: 64),
            sourceRenames: [],
            sourceDeletions: []
        )
        capture = try LifecycleAnalysisCapture(
            selection: selection,
            sources: [source],
            exclusions: [],
            maximumFileBytes: 1_024,
            gitBeforeRead: snapshot,
            gitAfterRead: snapshot
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension GitHistoryProcessResult {
    fileprivate static func success(_ stdout: String) -> GitHistoryProcessResult {
        GitHistoryProcessResult(exitCode: 0, stdout: stdout, stderr: "", timedOut: false)
    }
}
