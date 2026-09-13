import Foundation
import SCMACore
import Testing

@testable import SCMAKit

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
        #expect(result.evidence.map(\.kind) == [
            "git-history.change-frequency",
            "git-history.contributor-concentration",
            "git-history.fix-orientation",
            "git-history.recency",
        ])
        #expect(result.evidence.allSatisfy { $0.availability.isAvailable })
        #expect(result.evidence.first { $0.kind == "git-history.change-frequency" }?.rawValue == "commits=2;window=all")
        #expect(result.evidence.first { $0.kind == "git-history.fix-orientation" }?.rawValue.contains("fixCommits=1") == true)
        #expect(result.evidence.first { $0.kind == "git-history.contributor-concentration" }?.rawValue == "uniqueContributors=2;topShare=0.500")
        #expect(
            result.evidence.first { $0.kind == "git-history.recency" }?.rawValue
                == "lastChangeDaysAgo=2;lastChangedAt=2026-09-10T00:00:00Z;referenceTime=2026-09-12T00:00:00Z"
        )
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
        runner.enqueue(.init(
            exitCode: 0,
            stdout: "\u{1e}abcdef\u{1f}dev@example.test\u{1f}2026-09-10T00:00:00Z\u{1f}fix: repair\nSources/A.swift\n",
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

        _ = provider.evidence(for: .init(
            repositoryRoot: "/tmp/repo with spaces",
            referenceTime: referenceTime,
            entities: [gitFixtureEntity(id: "file:Sources/A.swift", file: "Sources/A.swift")]
        ))

        #expect(runner.calls.map(\.arguments) == [
            ["git", "-C", "/tmp/repo with spaces", "rev-parse", "--is-inside-work-tree"],
            ["git", "-C", "/tmp/repo with spaces", "rev-parse", "--is-shallow-repository"],
            ["git", "-C", "/tmp/repo with spaces", "rev-list", "--count", "HEAD"],
            [
                "git", "-C", "/tmp/repo with spaces", "log", "--max-count=500",
                "--format=%x1e%H%x1f%aE%x1f%aI%x1f%s", "--name-only", "--", "Sources/A.swift",
            ],
        ])
        #expect(runner.calls.allSatisfy { call in !call.arguments.contains { $0.contains("git -C") } })
    }
}
