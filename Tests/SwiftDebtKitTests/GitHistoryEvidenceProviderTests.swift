import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("Git history evidence provider")
struct GitHistoryEvidenceProviderTests {
    @Test func temporaryRepositoryWithFrozenTimestampsProducesHistoryEvidence() throws {
        let root = try temporaryGitTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try initializeGitRepository(at: root)
        try writeGitFixture("struct Alpha { func run() {} }\n", name: "Sources/Alpha.swift", root: root)
        try commitGitFixture(
            root: root,
            message: "feat: add alpha",
            authorEmail: "alice@example.test",
            timestamp: "2026-09-01T00:00:00Z"
        )
        try writeGitFixture("struct Alpha { func run() { print(1) } }\n", name: "Sources/Alpha.swift", root: root)
        try commitGitFixture(
            root: root,
            message: "fix: repair alpha crash",
            authorEmail: "bob@example.test",
            timestamp: "2026-09-10T00:00:00Z"
        )

        let referenceTime = try #require(ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z"))
        let request = GitHistoryEvidenceRequest(
            repositoryRoot: root.path,
            referenceTime: referenceTime,
            entities: [gitFixtureEntity(id: "file:Sources/Alpha.swift", file: "Sources/Alpha.swift")]
        )

        let result = GitHistoryEvidenceProvider(timeoutSeconds: 5).evidence(for: request)

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.evidence.map(\.kind) == [
                "git-history.change-frequency",
                "git-history.contributor-concentration",
                "git-history.fix-orientation",
                "git-history.recency",
            ])
        #expect(result.evidence.allSatisfy { $0.availability.isAvailable })
        #expect(
            result.evidence.first { $0.kind == "git-history.change-frequency" }?.rawValue
                == "commits=2;window=last-500-file-commits;truncated=false"
        )
        #expect(
            result.evidence.first { $0.kind == "git-history.fix-orientation" }?.rawValue.contains("fixCommits=1")
                == true)
        #expect(
            result.evidence.first { $0.kind == "git-history.contributor-concentration" }?.rawValue
                == "uniqueContributors=2;topShare=0.500")
        #expect(
            result.evidence.first { $0.kind == "git-history.recency" }?.rawValue
                == "lastChangeDaysAgo=2;lastChangedAt=2026-09-10T00:00:00Z;referenceTime=2026-09-12T00:00:00Z"
        )
    }

    @Test func renamedFileRetainsEarlierHistory() throws {
        let root = try temporaryGitTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try initializeGitRepository(at: root)
        try writeGitFixture("struct Before {}\n", name: "Sources/Before.swift", root: root)
        try commitGitFixture(
            root: root,
            message: "feat: add original file",
            authorEmail: "history@example.test",
            timestamp: "2026-09-01T00:00:00Z"
        )
        try runGitFixture(["mv", "Sources/Before.swift", "Sources/After.swift"], root: root)
        try commitGitFixture(
            root: root,
            message: "refactor: rename file",
            authorEmail: "history@example.test",
            timestamp: "2026-09-02T00:00:00Z"
        )
        let referenceTime = try #require(ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z"))

        let result = GitHistoryEvidenceProvider().evidence(
            for: .init(
                repositoryRoot: root.path,
                referenceTime: referenceTime,
                entities: [gitFixtureEntity(id: "file:Sources/After.swift", file: "Sources/After.swift")]
            )
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.evidence.first { $0.kind == "git-history.change-frequency" }?.rawValue
                == "commits=2;window=last-500-file-commits;truncated=false"
        )
    }

    @Test func boundedHistoryReportsTruncationTruthfully() throws {
        let runner = RecordingGitRunner()
        runner.enqueue(.init(exitCode: 0, stdout: "true\n", stderr: "", timedOut: false))
        runner.enqueue(.init(exitCode: 0, stdout: "false\n", stderr: "", timedOut: false))
        runner.enqueue(.init(exitCode: 0, stdout: "1\n", stderr: "", timedOut: false))
        runner.enqueue(.init(exitCode: 0, stdout: gitLogFixture(commitCount: 501), stderr: "", timedOut: false))
        let provider = GitHistoryEvidenceProvider(runner: runner)
        let referenceTime = try #require(ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z"))

        let result = provider.evidence(
            for: .init(
                repositoryRoot: "/tmp/repository",
                referenceTime: referenceTime,
                entities: [gitFixtureEntity(id: "file:Sources/A.swift", file: "Sources/A.swift")]
            )
        )

        #expect(
            result.evidence.first { $0.kind == "git-history.change-frequency" }?.rawValue
                == "commits=500;window=last-500-file-commits;truncated=true"
        )
        #expect(runner.calls.last?.arguments.contains("--max-count=501") == true)
        #expect(runner.calls.last?.arguments.contains("--follow") == true)
    }

    @Test func sameRepositoryAndReferenceTimeProduceStableEvidence() throws {
        let root = try temporaryGitTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try initializeGitRepository(at: root)
        try writeGitFixture("struct Stable { func run() {} }\n", name: "Sources/Stable.swift", root: root)
        try commitGitFixture(
            root: root,
            message: "fix: stabilize history",
            authorEmail: "stable@example.test",
            timestamp: "2026-09-05T00:00:00Z"
        )
        let referenceTime = try #require(ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z"))
        let request = GitHistoryEvidenceRequest(
            repositoryRoot: root.path,
            referenceTime: referenceTime,
            entities: [gitFixtureEntity(id: "file:Sources/Stable.swift", file: "Sources/Stable.swift")]
        )
        let provider = GitHistoryEvidenceProvider(timeoutSeconds: 5)

        let first = provider.evidence(for: request)
        let second = provider.evidence(for: request)

        #expect(first == second)
        #expect(first.evidence.allSatisfy { $0.availability.isAvailable })
    }

    @Test(arguments: [UnavailableRepositoryCase.nonRepository, .noHistory, .shallow])
    func unavailableRepositoryHistoryDoesNotFabricateZeroes(testCase: UnavailableRepositoryCase) throws {
        let root = try temporaryGitTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try testCase.makeRepository(in: root)
        let referenceTime = try #require(ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z"))
        let result = GitHistoryEvidenceProvider(timeoutSeconds: 5).evidence(
            for: GitHistoryEvidenceRequest(
                repositoryRoot: repository.path,
                referenceTime: referenceTime,
                entities: [gitFixtureEntity(id: "file:Sources/Missing.swift", file: "Sources/Missing.swift")]
            )
        )

        #expect(result.evidence.count == 4)
        #expect(result.evidence.allSatisfy { !$0.availability.isAvailable })
        #expect(result.evidence.allSatisfy { $0.normalizedScore == nil })
        #expect(result.evidence.allSatisfy { $0.rawValue == "unavailable" })
        #expect(result.evidence.allSatisfy { $0.availability.reason?.contains(testCase.reasonFragment) == true })
        #expect(result.diagnostics.first?.message.contains(testCase.reasonFragment) == true)
    }

    @Test func providerPassesProcessArgumentsStructurally() throws {
        let runner = RecordingGitRunner()
        runner.enqueue(.init(exitCode: 0, stdout: "true\n", stderr: "", timedOut: false))
        runner.enqueue(.init(exitCode: 0, stdout: "false\n", stderr: "", timedOut: false))
        runner.enqueue(.init(exitCode: 0, stdout: "1\n", stderr: "", timedOut: false))
        runner.enqueue(
            .init(
                exitCode: 0,
                stdout:
                    "\u{1e}abcdef\u{1f}dev@example.test\u{1f}2026-09-10T00:00:00Z\u{1f}fix: repair\nSources/A.swift\n",
                stderr: "",
                timedOut: false
            ))
        let provider = GitHistoryEvidenceProvider(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            baseArguments: ["git"],
            timeoutSeconds: 5,
            runner: runner
        )
        let referenceTime = try #require(ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z"))

        _ = provider.evidence(
            for: .init(
                repositoryRoot: "/tmp/repo with spaces",
                referenceTime: referenceTime,
                entities: [gitFixtureEntity(id: "file:Sources/A.swift", file: "Sources/A.swift")]
            ))

        #expect(
            runner.calls.map(\.arguments) == [
                ["git", "-C", "/tmp/repo with spaces", "rev-parse", "--is-inside-work-tree"],
                ["git", "-C", "/tmp/repo with spaces", "rev-parse", "--is-shallow-repository"],
                ["git", "-C", "/tmp/repo with spaces", "rev-list", "--count", "HEAD"],
                [
                    "git", "-C", "/tmp/repo with spaces", "log", "--follow", "--max-count=501",
                    "--format=%x1e%H%x1f%aE%x1f%aI%x1f%s", "--name-only", "--", "Sources/A.swift",
                ],
            ])
        #expect(runner.calls.allSatisfy { call in !call.arguments.contains { $0.contains("git -C") } })
    }
    @Test func subprocessRunnerTerminatesAtConfiguredTimeout() throws {
        let directory = try temporaryGitTestDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = GitHistorySubprocessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "sleep 1"],
            workingDirectory: directory,
            timeoutSeconds: 0.01
        )

        #expect(result.timedOut)
    }
}

private func gitLogFixture(commitCount: Int) -> String {
    (0..<commitCount).map { index in
        "\u{1e}\(String(format: "%040d", index))\u{1f}dev@example.test\u{1f}2026-09-10T00:00:00Z\u{1f}change \(index)\nSources/A.swift\n"
    }.joined()
}
