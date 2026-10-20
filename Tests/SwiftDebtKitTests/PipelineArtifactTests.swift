import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("Pipeline artifact integrity")
struct PipelineArtifactTests {
    @Test func passesArgumentsLiterallyWithoutAShell() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let artifacts = root.appendingPathComponent("artifacts")
        let literal = "$(touch unexpected); * $HOME 'quoted'"
        let report = try PipelineService().run(
            configuration: makeConfiguration(commands: [
                PipelineCommand(
                    check: .staticAnalysis,
                    executable: "/usr/bin/printf",
                    arguments: ["%s", literal]
                )
            ]),
            workingDirectory: root,
            artifactsDirectory: artifacts
        )
        #expect(status(of: .staticAnalysis, in: report) == .passed)
        #expect(try text("staticAnalysis.stdout.log", in: artifacts) == literal)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("unexpected").path))
    }

    @Test func writesPlanAndEachResultBeforeContinuing() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let artifacts = root.appendingPathComponent("artifacts")
        let report = try PipelineService().run(
            configuration: makeConfiguration(commands: [
                shell(
                    .staticAnalysis,
                    "test -f \"$1/plan.json\" && test ! -f \"$1/report.json\"",
                    trailing: [artifacts.path]
                ),
                shell(
                    .architecture,
                    "test -f \"$1/staticAnalysis.result.json\" && test ! -f \"$1/report.json\"",
                    trailing: [artifacts.path]
                ),
            ]),
            workingDirectory: root,
            artifactsDirectory: artifacts
        )
        #expect(status(of: .staticAnalysis, in: report) == .passed)
        #expect(status(of: .architecture, in: report) == .passed)
        let persistedPlan = try JSONDecoder().decode(
            PipelinePlan.self,
            from: Data(contentsOf: artifacts.appendingPathComponent("plan.json"))
        )
        #expect(persistedPlan == report.plan)
        for expected in report.evaluation.results {
            let result = try JSONDecoder().decode(
                PipelineCheckResult.self,
                from: Data(
                    contentsOf: artifacts.appendingPathComponent(
                        "\(expected.check.rawValue).result.json"))
            )
            #expect(result == expected)
        }
    }

    @Test func rejectsContradictoryOrUnsupportedReports() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let report = try PipelineService().run(
            configuration: makeConfiguration(),
            workingDirectory: root,
            artifactsDirectory: root.appendingPathComponent("artifacts")
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PipelineRunReport.self, from: data)
        #expect(decoded.evaluation == report.evaluation)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        var invalidSchema = object
        invalidSchema["schemaVersion"] = 2
        var invalidVerdict = object
        var evaluation = try #require(object["evaluation"] as? [String: Any])
        evaluation["verdict"] = "passed"
        invalidVerdict["evaluation"] = evaluation
        var missingResults = object
        evaluation["verdict"] = "inconclusive"
        evaluation["results"] = []
        missingResults["evaluation"] = evaluation
        for invalid in [invalidSchema, invalidVerdict, missingResults] {
            let tampered = try JSONSerialization.data(withJSONObject: invalid)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(PipelineRunReport.self, from: tampered)
            }
        }
    }
}
