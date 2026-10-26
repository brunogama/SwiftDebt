import Foundation
import SwiftDebtCore
import Testing

@Suite("CLI debt workflow subprocess integration")
struct CLIWorkflowTests {
    @Test func debtAnalyzeJSONSucceedsAndIsDeterministicWithoutTTY() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try runSwiftDebt([
            "debt", "analyze", directory.path, "--format", "json", "--top", "2", "--jobs", "1",
            "--coverage", "coverage.info",
        ])
        let second = try runSwiftDebt([
            "debt", "analyze", directory.path, "--format", "json", "--top", "2", "--jobs", "1",
            "--coverage", "coverage.info",
        ])

        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(first.stderr.isEmpty)
        #expect(second.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        let decoded = try JSONDecoder().decode(DebtReport.self, from: Data(first.stdout.utf8))
        #expect(decoded.reportKind == "swiftdebt-report")
        #expect(decoded.items.count <= 2)
    }

    @Test func invalidDebtAnalyzeArgumentsExitTwo() throws {
        let result = try runSwiftDebt(["debt", "analyze", "--top", "nope"])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Invalid integer for --top"))
    }

    @Test(arguments: [["analyze"], ["debt", "analyze"]])
    func invalidMaximumFileBytesExitsTwo(command: [String]) throws {
        let result = try runSwiftDebt(command + ["--max-file-bytes", "0"])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("max-file-bytes"))
    }

    @Test(arguments: [["analyze"], ["debt", "analyze"]])
    func maximumFileBytesRejectsOversizedSources(command: [String]) throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt(command + [directory.path, "--max-file-bytes", "1", "--jobs", "1"])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("File exceeds maximumFileBytes"))
    }

    @Test func maximumFileBytesOverridesConfiguration() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        {"maximumFileBytes":1}
        """.write(
            to: directory.appendingPathComponent(".swift-debt.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runSwiftDebt([
            "debt", "analyze", directory.path, "--max-file-bytes", "4096", "--jobs", "1",
        ])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.hasPrefix("PRIORITY | SCORE | ENTITY | LOCATION | CATEGORY | ACTION\n"))
    }

    @Test func explainCoverageHonorsMaximumFileBytes() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt([
            "explain", "coverage", directory.path, "--lcov", "coverage.info", "--max-file-bytes", "1",
        ])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("File exceeds maximumFileBytes"))
    }

    @Test func debtValidateSucceedsWhenScoresAreWithinThreshold() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt([
            "debt", "validate", directory.path, "--max-score", "100", "--top", "1", "--jobs", "1",
        ])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Debt validation passed: max-score 100.0"))
        #expect(result.stderr.isEmpty)
    }

    @Test func debtValidateGateFailureExitsOneAndCanBeQuiet() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt([
            "debt", "validate", directory.path, "--max-score", "0", "--top", "1", "--jobs", "1", "--quiet",
        ])

        #expect(result.status == 1)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.isEmpty)
    }

    @Test func existingAnalyzeFormsRemainSwiftDebtJSONWorkflows() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let explicit = try runSwiftDebt(["analyze", directory.path, "--format", "json", "--jobs", "1"])
        let implicit = try runSwiftDebt([directory.path, "--format", "json", "--jobs", "1"])

        #expect(explicit.status == 0)
        #expect(implicit.status == 0)
        #expect(explicit.stderr.isEmpty)
        #expect(implicit.stderr.isEmpty)
        _ = try JSONDecoder().decode(AnalysisReport.self, from: Data(explicit.stdout.utf8))
        _ = try JSONDecoder().decode(AnalysisReport.self, from: Data(implicit.stdout.utf8))
    }

    @Test func implicitAnalyzePathNamedDebtRemainsSwiftDebtJSONWorkflow() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-debt-cli-tests-\(UUID().uuidString)")
        _ = try makeTemporaryProject(named: "debt", in: parent)
        defer { try? FileManager.default.removeItem(at: parent) }

        let result = try runSwiftDebt(["debt", "--format", "json", "--jobs", "1"], currentDirectory: parent)

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        _ = try JSONDecoder().decode(AnalysisReport.self, from: Data(result.stdout.utf8))
    }

    private func makeTemporaryProject(named name: String? = nil, in parent: URL? = nil) throws -> URL {
        let directory = (parent ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(name ?? "swift-debt-cli-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        final class Worker {
            func run(_ value: Int) {
                if value > 0 { print(value) }
                if value > 1 { print(value - 1) }
            }
        }
        """.write(to: directory.appendingPathComponent("Worker.swift"), atomically: true, encoding: .utf8)
        try "".write(to: directory.appendingPathComponent("coverage.info"), atomically: true, encoding: .utf8)
        return directory
    }
}
