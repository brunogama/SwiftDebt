import Foundation
import SwiftDebtCore
import Testing

@Suite("CLI Git-history reference time")
struct HistoryReferenceCLIWorkflowTests {
    @Test func absentReferenceTimeDoesNotFabricateEpochRecency() throws {
        let directory = try makeTemporaryGitProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt([
            "debt", "analyze", directory.path, "--format", "json", "--aggregation", "none", "--jobs", "1",
        ])
        let report = try JSONDecoder().decode(DebtReport.self, from: Data(result.stdout.utf8))
        let historyEvidence = report.items.flatMap(\.evidence).filter { $0.kind.hasPrefix("git-history.") }

        #expect(result.status == 0)
        #expect(!historyEvidence.isEmpty)
        #expect(historyEvidence.allSatisfy { !$0.availability.isAvailable })
        #expect(
            report.missingEvidence.contains { missing in
                missing.kind.hasPrefix("git-history.") && missing.reason.contains("reference time")
            })
        #expect(!result.stdout.contains("referenceTime=1970-01-01T00:00:00Z"))
        #expect(!result.stdout.contains("lastChangeDaysAgo=0"))
    }

    @Test func cliReferenceTimeControlsGitRecency() throws {
        let directory = try makeTemporaryGitProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt([
            "debt", "analyze", directory.path, "--format", "json", "--aggregation", "none", "--jobs", "1",
            "--debt-reference-time", "2026-09-12T00:00:00Z",
        ])
        let report = try JSONDecoder().decode(DebtReport.self, from: Data(result.stdout.utf8))
        let recency = report.items.flatMap(\.evidence).first { $0.kind == "git-history.recency" }

        #expect(result.status == 0)
        #expect(recency?.availability.isAvailable == true)
        #expect(
            recency?.rawValue
                == "lastChangeDaysAgo=2;lastChangedAt=2026-09-10T00:00:00Z;referenceTime=2026-09-12T00:00:00Z"
        )
    }

    @Test func configuredReferenceTimeControlsGitRecency() throws {
        let directory = try makeTemporaryGitProject()
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        {
          "debtReferenceTime": "2026-09-12T00:00:00Z"
        }
        """.write(
            to: directory.appendingPathComponent(".swift-debt.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runSwiftDebt([
            "debt", "analyze", directory.path, "--format", "json", "--aggregation", "none", "--jobs", "1",
        ])
        let report = try JSONDecoder().decode(DebtReport.self, from: Data(result.stdout.utf8))
        let recency = report.items.flatMap(\.evidence).first { $0.kind == "git-history.recency" }

        #expect(result.status == 0)
        #expect(recency?.availability.isAvailable == true)
        #expect(
            recency?.rawValue
                == "lastChangeDaysAgo=2;lastChangedAt=2026-09-10T00:00:00Z;referenceTime=2026-09-12T00:00:00Z"
        )
    }

    @Test func invalidCLIReferenceTimeExitsTwoWithActionableError() throws {
        let result = try runSwiftDebt(["debt", "analyze", "--debt-reference-time", "not-a-timestamp"])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Invalid ISO-8601 timestamp for --debt-reference-time: not-a-timestamp"))
        #expect(result.stderr.contains("expected 2026-09-12T00:00:00Z"))
    }

    @Test func invalidConfiguredReferenceTimeExitsTwoAndNamesConfiguration() throws {
        let directory = try makeTemporaryGitProject()
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        {"debtReferenceTime":"not-a-timestamp"}
        """.write(
            to: directory.appendingPathComponent(".swift-debt.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runSwiftDebt(["debt", "analyze", directory.path, "--format", "json"])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains(".swift-debt.json"))
        #expect(result.stderr.contains("debtReferenceTime must be an ISO-8601 timestamp"))
    }

    private func makeTemporaryGitProject() throws -> URL {
        let directory = try temporaryGitTestDirectory()
        try initializeGitRepository(at: directory)
        try writeGitFixture(
            """
            final class Worker {
                func run(_ value: Int) {
                    if value > 0 { print(value) }
                }
            }
            """,
            name: "Sources/Worker.swift",
            root: directory
        )
        try commitGitFixture(
            root: directory,
            message: "feat: add worker",
            authorEmail: "worker@example.test",
            timestamp: "2026-09-10T00:00:00Z"
        )
        return directory
    }
}
