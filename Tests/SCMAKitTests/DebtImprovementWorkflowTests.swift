import Foundation
import SCMACore
import SCMAKit
import Testing

@Suite("Debt improvement workflows")
struct DebtImprovementWorkflowTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func goldenBeforeAfterComparisonIsDeterministicAndSchemaAware() throws {
        let before: DebtReport = try loadJSON("Tests/SCMAKitTests/Fixtures/DebtImprovement/before-report.fixture.json")
        let after: DebtReport = try loadJSON("Tests/SCMAKitTests/Fixtures/DebtImprovement/after-report.fixture.json")

        let comparison = try DebtReportComparator().compare(before: before, after: after)
        let repeated = try DebtReportComparator().compare(before: before, after: after)
        let shuffled = try DebtReportComparator().compare(before: shuffledReport(before), after: shuffledReport(after))
        let rendered = try renderJSON(comparison)

        #expect(comparison.schemaVersion == 1)
        #expect(comparison.beforeReportSchemaVersion == DebtReportSchema.currentVersion)
        #expect(comparison.afterReportSchemaVersion == DebtReportSchema.currentVersion)
        #expect(comparison.itemChanges.added.map { $0.id } == ["callable:New.feature"])
        #expect(comparison.itemChanges.removed.map { $0.id } == ["callable:Legacy.clean"])
        #expect(comparison.itemChanges.changed.map { $0.id } == ["callable:Service.run"])
        #expect(comparison.itemChanges.changed.first?.moved == true)
        #expect(comparison.itemChanges.changed.first?.unavailableEvidence.removed == ["callable:Service.run:coverage"])
        #expect(comparison.aggregationChanges.changed.map { $0.id } == ["file:Sources/App.swift"])
        let shuffledRendering = try renderJSON(shuffled)
        let expectedComparison = try read("Tests/SCMAKitTests/Fixtures/DebtImprovement/comparison.golden.json")

        #expect(comparison == repeated)
        #expect(comparison == shuffled)
        #expect(rendered == shuffledRendering)
        #expect(rendered == expectedComparison)

        var unsupported = before
        unsupported = DebtReport(
            schemaVersion: DebtReportSchema.currentVersion + 1,
            reportKind: unsupported.reportKind,
            generator: unsupported.generator,
            options: unsupported.options,
            summary: unsupported.summary,
            items: unsupported.items,
            aggregations: unsupported.aggregations,
            compactItems: unsupported.compactItems,
            missingEvidence: unsupported.missingEvidence
        )
        #expect(throws: AnalysisFailure.self) {
            _ = try DebtReportComparator().compare(before: unsupported, after: after)
        }
    }

    @Test func validationRendersMachineReadableResultAndAutomationExitStatuses() async throws {
        let beforePath = fixturePath("Tests/SCMAKitTests/Fixtures/DebtImprovement/before-report.fixture.json")
        let afterPath = fixturePath("Tests/SCMAKitTests/Fixtures/DebtImprovement/after-report.fixture.json")
        let service = DebtImprovementService()

        let passing = try service.validateImprovement(.init(beforePath: beforePath, afterPath: afterPath, minimumImprovement: 5))
        let failing = try service.validateImprovement(.init(beforePath: beforePath, afterPath: afterPath, minimumImprovement: 6))

        let expectedPassing = try read("Tests/SCMAKitTests/Fixtures/DebtImprovement/validation-pass.golden.json")
        let expectedFailing = try read("Tests/SCMAKitTests/Fixtures/DebtImprovement/validation-fail.golden.json")

        #expect(passing.exitStatus == 0)
        #expect(failing.exitStatus == 1)
        #expect(passing.standardOutput == expectedPassing)
        #expect(failing.standardOutput == expectedFailing)
    }

    @Test func validationExecutableReturnsNonzeroStatusWhenImprovementGateFails() throws {
        let beforePath = fixturePath("Tests/SCMAKitTests/Fixtures/DebtImprovement/before-report.fixture.json")
        let afterPath = fixturePath("Tests/SCMAKitTests/Fixtures/DebtImprovement/after-report.fixture.json")
        let result = try runSCMAExecutable(arguments: [
            "validate-improvement", beforePath, afterPath, "--threshold", "6",
        ])
        let expectedFailing = try read("Tests/SCMAKitTests/Fixtures/DebtImprovement/validation-fail.golden.json")

        #expect(result.exitStatus == 1)
        #expect(result.standardOutput == expectedFailing)
        #expect(result.standardError == "")
    }

    private func loadJSON<T: Decodable>(_ path: String) throws -> T {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func fixturePath(_ path: String) -> String {
        root.appendingPathComponent(path).path
    }

    private func renderJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    private func runSCMAExecutable(arguments: [String]) throws -> CommandResult {
        let executable = try scmaExecutablePath()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        return CommandResult(
            standardOutput: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            standardError: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            exitStatus: process.terminationStatus
        )
    }

    private func scmaExecutablePath() throws -> URL {
        let executable = root.appendingPathComponent(".build/debug/scma")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MissingExecutable(path: executable.path)
        }
        return executable
    }

    private func shuffledReport(_ report: DebtReport) -> DebtReport {
        DebtReport(
            schemaVersion: report.schemaVersion,
            reportKind: report.reportKind,
            generator: report.generator,
            options: report.options,
            summary: report.summary,
            items: Array(report.items.reversed()),
            aggregations: Array(report.aggregations.reversed()),
            compactItems: Array(report.compactItems.reversed()),
            missingEvidence: Array(report.missingEvidence.reversed())
        )
    }

    private struct CommandResult {
        let standardOutput: String
        let standardError: String
        let exitStatus: Int32
    }

    private struct MissingExecutable: Error, CustomStringConvertible {
        let path: String

        var description: String {
            "Missing scma executable at \(path); run swift build --build-tests before swift test"
        }
    }
}
