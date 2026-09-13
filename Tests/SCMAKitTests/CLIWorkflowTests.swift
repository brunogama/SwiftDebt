import Foundation
import SCMACore
import Testing

@Suite("CLI debt workflow subprocess integration")
struct CLIWorkflowTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func debtAnalyzeJSONSucceedsAndIsDeterministicWithoutTTY() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try runSCMA([
            "debt", "analyze", directory.path, "--format", "json", "--top", "2", "--jobs", "1",
            "--coverage", "coverage.info",
        ])
        let second = try runSCMA([
            "debt", "analyze", directory.path, "--format", "json", "--top", "2", "--jobs", "1",
            "--coverage", "coverage.info",
        ])

        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(first.stderr.isEmpty)
        #expect(second.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        let decoded = try JSONDecoder().decode(DebtReport.self, from: Data(first.stdout.utf8))
        #expect(decoded.reportKind == "swiftscma-debt-report")
        #expect(decoded.items.count <= 2)
    }

    @Test func invalidDebtAnalyzeArgumentsExitTwo() throws {
        let result = try runSCMA(["debt", "analyze", "--top", "nope"])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Invalid integer for --top"))
    }

    @Test func debtValidateSucceedsWhenScoresAreWithinThreshold() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSCMA([
            "debt", "validate", directory.path, "--max-score", "100", "--top", "1", "--jobs", "1",
        ])

        #expect(result.status == 0)
        #expect(result.stdout.contains("Debt validation passed: max-score 100.0"))
        #expect(result.stderr.isEmpty)
    }

    @Test func debtValidateGateFailureExitsOneAndCanBeQuiet() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSCMA([
            "debt", "validate", directory.path, "--max-score", "0", "--top", "1", "--jobs", "1", "--quiet",
        ])

        #expect(result.status == 1)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.isEmpty)
    }

    @Test func existingAnalyzeFormsRemainSCMAJSONWorkflows() throws {
        let directory = try makeTemporaryProject()
        defer { try? FileManager.default.removeItem(at: directory) }

        let explicit = try runSCMA(["analyze", directory.path, "--format", "json", "--jobs", "1"])
        let implicit = try runSCMA([directory.path, "--format", "json", "--jobs", "1"])

        #expect(explicit.status == 0)
        #expect(implicit.status == 0)
        #expect(explicit.stderr.isEmpty)
        #expect(implicit.stderr.isEmpty)
        _ = try JSONDecoder().decode(AnalysisReport.self, from: Data(explicit.stdout.utf8))
        _ = try JSONDecoder().decode(AnalysisReport.self, from: Data(implicit.stdout.utf8))
    }

    @Test func implicitAnalyzePathNamedDebtRemainsSCMAJSONWorkflow() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("scma-cli-tests-\(UUID().uuidString)")
        _ = try makeTemporaryProject(named: "debt", in: parent)
        defer { try? FileManager.default.removeItem(at: parent) }

        let result = try runSCMA(["debt", "--format", "json", "--jobs", "1"], currentDirectory: parent)

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        _ = try JSONDecoder().decode(AnalysisReport.self, from: Data(result.stdout.utf8))
    }

    private func makeTemporaryProject(named name: String? = nil, in parent: URL? = nil) throws -> URL {
        let directory = (parent ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(name ?? "scma-cli-tests-\(UUID().uuidString)")
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

    private func runSCMA(_ arguments: [String], currentDirectory: URL? = nil) throws -> CLIRunResult {
        let process = Process()
        process.executableURL = try scmaExecutableURL()
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory ?? root
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CI": "1",
            "TERM": "dumb",
        ]) { _, new in new }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return CLIRunResult(
            status: process.terminationStatus,
            stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func scmaExecutableURL() throws -> URL {
        let direct = root.appendingPathComponent(".build/debug/scma")
        if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
        let build = root.appendingPathComponent(".build")
        guard let enumerator = FileManager.default.enumerator(at: build, includingPropertiesForKeys: nil) else {
            throw CLIWorkflowTestError(message: "Missing .build directory")
        }
        let matches = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.lastPathComponent == "scma", url.path.contains("/debug/") else {
                return nil
            }
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }.sorted { lhs, rhs in
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return lhs.path < rhs.path
        }
        guard let match = matches.first else { throw CLIWorkflowTestError(message: "Could not locate built scma executable") }
        return match
    }
}

private struct CLIRunResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private struct CLIWorkflowTestError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
