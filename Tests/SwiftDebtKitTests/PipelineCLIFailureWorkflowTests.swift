import Foundation
import Testing

@Suite("Pipeline CLI evaluated outcomes")
struct PipelineCLIFailureWorkflowTests {
    @Test("A required command failure exits one and later commands still run")
    func requiredFailureExitsOneAndRetainsCompleteEvidence() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var commands = pipelineCLIPassingCommands()
        commands[0].arguments = ["-c", "printf failed-check\\n; exit 9"]
        let configuration = root.appendingPathComponent("pipeline.json")
        try writePipelineCLIConfiguration(at: configuration, commands: commands)

        let result = try runSwiftDebt(
            ["pipeline", "run", "pipeline.json", "--artifacts", "artifacts"],
            currentDirectory: root)
        let report = try decodePipelineCLIJSON(PipelineCLIObservedReport.self, from: result.stdout)
        let failed = try #require(
            report.evaluation.results.first { $0.check == "staticAnalysis" })
        let last = try #require(report.evaluation.results.first { $0.check == "endToEnd" })

        #expect(result.status == 1)
        #expect(result.stderr.isEmpty)
        #expect(report.evaluation.verdict == "failed")
        #expect(failed.status == "failed")
        #expect(last.status == "passed")
        #expect(
            try readPipelineCLIText(
                root.appendingPathComponent("artifacts/endToEnd.stdout.log"))
                == "endToEnd-stdout\n")
    }

    @Test("A missing required command is reported as unavailable and exits two")
    func missingEvidenceExitsTwo() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = root.appendingPathComponent("pipeline.json")
        try writePipelineCLIConfiguration(
            at: configuration, commands: [pipelineCLIPassingCommands()[0]])

        let result = try runSwiftDebt(
            ["pipeline", "run", "pipeline.json", "--artifacts", "artifacts"],
            currentDirectory: root)
        let report = try decodePipelineCLIJSON(PipelineCLIObservedReport.self, from: result.stdout)

        #expect(result.status == 2)
        #expect(result.stderr.isEmpty)
        #expect(report.evaluation.verdict == "inconclusive")
        #expect(report.evaluation.results.first?.status == "passed")
        #expect(report.evaluation.results.dropFirst().allSatisfy { $0.status == "unavailable" })
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("artifacts/architecture.stdout.log").path))
        #expect(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("artifacts/report.json").path))
    }

    @Test("A missing configured executable is unavailable and exits two")
    func missingExecutableExitsTwo() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var commands = pipelineCLIPassingCommands()
        commands[1].executable = "/definitely/missing/swiftdebt-pipeline-tool"
        let configuration = root.appendingPathComponent("pipeline.json")
        try writePipelineCLIConfiguration(at: configuration, commands: commands)

        let result = try runSwiftDebt(
            ["pipeline", "run", "pipeline.json", "--artifacts", "artifacts"],
            currentDirectory: root)
        let report = try decodePipelineCLIJSON(PipelineCLIObservedReport.self, from: result.stdout)
        let unavailable = try #require(
            report.evaluation.results.first { $0.check == "architecture" })
        let last = try #require(report.evaluation.results.first { $0.check == "endToEnd" })

        #expect(result.status == 2)
        #expect(result.stderr.isEmpty)
        #expect(report.evaluation.verdict == "inconclusive")
        #expect(unavailable.status == "unavailable")
        #expect(!unavailable.detail.isEmpty)
        #expect(last.status == "passed")
    }

    @Test("A required timeout exits one without preventing later evidence")
    func timeoutExitsOneAndContinues() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var commands = pipelineCLIPassingCommands()
        commands[3].arguments = ["-c", "while :; do :; done"]
        commands[3].timeoutSeconds = 0.05
        let configuration = root.appendingPathComponent("pipeline.json")
        try writePipelineCLIConfiguration(at: configuration, commands: commands)

        let result = try runSwiftDebt(
            ["pipeline", "run", "pipeline.json", "--artifacts", "artifacts"],
            currentDirectory: root)
        let report = try decodePipelineCLIJSON(PipelineCLIObservedReport.self, from: result.stdout)
        let timedOut = try #require(
            report.evaluation.results.first { $0.check == "integration" })
        let last = try #require(report.evaluation.results.first { $0.check == "endToEnd" })

        #expect(result.status == 1)
        #expect(result.stderr.isEmpty)
        #expect(report.evaluation.verdict == "failed")
        #expect(timedOut.status == "timedOut")
        #expect(last.status == "passed")
    }
}
