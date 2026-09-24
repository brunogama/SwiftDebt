import Foundation
import SwiftDebtCore
import SwiftDebtKit
import Testing

@Suite("CLI rule observation subprocess integration")
struct RuleAnalysisCLIWorkflowTests {
    @Test("Default text rule section matches the checked-in golden")
    func defaultTextRuleSectionGolden() throws {
        let directory = try makeProject(
            fileName: "Sources/App/Example.swift",
            source: """
                func load() -> Int {
                    try! dangerous()
                }
                func dangerous() throws -> Int { 1 }
                """
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try """
        // swift-tools-version: 6.2
        import PackageDescription

        let package = Package(name: "RuleFixture", targets: [.target(name: "App")])
        """.write(
            to: directory.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let first = try runSwiftDebt(["analyze", directory.path])
        let second = try runSwiftDebt(["analyze", directory.path])
        let marker = try #require(first.stdout.range(of: "RULE OBSERVATIONS\n"))
        let actualSection = String(first.stdout[marker.lowerBound...])
        let expectedSection = try String(
            contentsOf: fixtureURL("Fixtures/RuleAnalysis/force-try.golden.txt"),
            encoding: .utf8
        )

        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(first.stderr.isEmpty)
        #expect(second.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        #expect(actualSection == expectedSection)
    }

    @Test("A clean committed text run reports proven absence")
    func cleanTextRun() throws {
        let directory = try makeProject(fileName: "Clean.swift", source: "let value = 1")
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt(["analyze", directory.path, "--jobs", "1"])

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.contains("Status: complete | selected sources: 1 | committed sources: 1 | detections: 0"))
        #expect(result.stdout.contains("No detections in committed sources."))
    }

    @Test("A parse failure makes text rule analysis incomplete and exits two")
    func parseFailedTextRun() throws {
        let directory = try makeProject(fileName: "Invalid.swift", source: "func broken( {")
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt(["analyze", directory.path, "--jobs", "1"])

        #expect(result.status == 2)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout.split(separator: "\n").first?.hasSuffix(" - INCOMPLETE") == true)
        #expect(
            result.stdout.contains(
                "Status: INCOMPLETE | selected sources: 1 | committed sources: 0 | detections: 0"
            )
        )
        #expect(result.stdout.contains("Invalid.swift:1:"))
        #expect(result.stdout.contains("parse-failed error:"))
        #expect(result.stdout.contains("Absence was not established for incomplete sources."))
        #expect(!result.stdout.contains("No detections in committed sources."))
    }

    @Test("JSON output keeps the schema 2 transport free of rule text")
    func jsonTransportIsUnchangedByRuleAnalysis() throws {
        let directory = try makeProject(
            fileName: "Example.swift",
            source: "func load() -> Int { try! dangerous() }\nfunc dangerous() throws -> Int { 1 }"
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try runSwiftDebt(["analyze", directory.path, "--format", "json", "--jobs", "1"])
        let report = try JSONDecoder().decode(AnalysisReport.self, from: Data(result.stdout.utf8))

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(report.schemaVersion == 2)
        #expect(!result.stdout.contains("RULE OBSERVATIONS"))
        #expect(!result.stdout.contains("swiftdebt.force-try"))
    }

    @Test("Analysis service returns the canonical text snapshot")
    func textAnalysisRunResultCarriesSnapshot() async throws {
        let directory = try makeProject(fileName: "Input.swift", source: "let value = try! read()")
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await AnalysisService().run(AnalysisRequest(path: directory.path, jobs: 1))
        let snapshot = try #require(result.ruleAnalysisSnapshot)

        #expect(snapshot.isComplete)
        #expect(snapshot.detections.count == 1)
        #expect(snapshot.ruleDescriptor.identity.description == "swiftdebt.force-try")
    }

    private func makeProject(fileName: String, source: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-debt-rule-cli-tests-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent(fileName)
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try source.write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )
        return directory
    }

    private func fixtureURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(relativePath)
    }
}
