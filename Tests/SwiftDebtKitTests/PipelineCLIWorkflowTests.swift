import Foundation
import Testing

@Suite("Pipeline CLI subprocess workflows")
struct PipelineCLIWorkflowTests {
    @Test("Plan is deterministic JSON and executes no configured command")
    func planIsDeterministicWithoutSideEffects() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationDirectory = root.appendingPathComponent(
            "configuration with spaces", isDirectory: true)
        try FileManager.default.createDirectory(
            at: configurationDirectory, withIntermediateDirectories: true)
        let configuration = configurationDirectory.appendingPathComponent("pipeline config.json")
        let marker = configurationDirectory.appendingPathComponent("plan-command-ran")
        try writePipelineCLIConfiguration(
            at: configuration,
            commands: [
                PipelineCLICommandFixture(
                    check: "staticAnalysis",
                    arguments: ["-c", "printf ran > plan-command-ran"])
            ])
        let originalConfiguration = try Data(contentsOf: configuration)
        let arguments = ["pipeline", "plan", "configuration with spaces/pipeline config.json"]

        let first = try runSwiftDebt(arguments, currentDirectory: root)
        let second = try runSwiftDebt(arguments, currentDirectory: root)
        let plan = try decodePipelineCLIJSON(PipelineCLIObservedPlan.self, from: first.stdout)
        let canonical = try canonicalPipelineCLIJSON(plan)

        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(first.stderr.isEmpty)
        #expect(second.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        #expect(first.stdout == canonical)
        #expect(
            plan.context
                == PipelineCLIObservedContext(risk: "low", trigger: "pullRequest", impact: "known"))
        #expect(plan.requirements.map(\.check) == pipelineCLIKnownPullRequestChecks)
        #expect(plan.requirements.allSatisfy { $0.required })
        #expect(plan.requirements.allSatisfy { !$0.reason.isEmpty })
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(try Data(contentsOf: configuration) == originalConfiguration)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: configurationDirectory.path).sorted()
                == ["pipeline config.json"])
    }

    @Test("Run resolves spaced paths and writes a complete passing evidence bundle")
    func runWritesPassingReportAndLogsFromConfigurationDirectory() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let invocationDirectory = root.appendingPathComponent(
            "invocation directory with spaces", isDirectory: true)
        let configurationDirectory = invocationDirectory.appendingPathComponent(
            "configuration parent with spaces", isDirectory: true)
        try FileManager.default.createDirectory(
            at: configurationDirectory, withIntermediateDirectories: true)
        let configuration = configurationDirectory.appendingPathComponent("pipeline config.json")
        var commands = pipelineCLIPassingCommands()
        commands[0].arguments = [
            "-c",
            "printf cwd > command-relative-output.txt; pwd; "
                + "printf 'child-success-token\\n'; printf 'child-error-token\\n' >&2",
        ]
        try writePipelineCLIConfiguration(at: configuration, commands: commands)

        let result = try runSwiftDebt(
            [
                "pipeline", "run", "configuration parent with spaces/pipeline config.json",
                "--artifacts", "pipeline artifacts with spaces",
            ],
            currentDirectory: invocationDirectory)
        let artifacts = invocationDirectory.appendingPathComponent(
            "pipeline artifacts with spaces", isDirectory: true)
        let report = try decodePipelineCLIJSON(PipelineCLIObservedReport.self, from: result.stdout)
        let canonical = try canonicalPipelineCLIJSON(report)

        #expect(result.status == 0)
        #expect(result.stderr.isEmpty)
        #expect(result.stdout == canonical)
        #expect(!result.stdout.contains("child-success-token"))
        #expect(!result.stdout.contains("child-error-token"))
        #expect(report.schemaVersion == 1)
        #expect(report.plan.requirements.map(\.check) == pipelineCLIKnownPullRequestChecks)
        #expect(report.evaluation.verdict == "passed")
        #expect(report.evaluation.results.map(\.check) == pipelineCLIKnownPullRequestChecks)
        #expect(report.evaluation.results.allSatisfy { $0.status == "passed" })
        #expect(
            FileManager.default.fileExists(
                atPath: configurationDirectory.appendingPathComponent(
                    "command-relative-output.txt"
                ).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: invocationDirectory.appendingPathComponent(
                    "command-relative-output.txt"
                ).path))

        for check in pipelineCLIKnownPullRequestChecks {
            #expect(
                FileManager.default.fileExists(
                    atPath: artifacts.appendingPathComponent("\(check).stdout.log").path))
            #expect(
                FileManager.default.fileExists(
                    atPath: artifacts.appendingPathComponent("\(check).stderr.log").path))
        }
        #expect(
            try readPipelineCLIText(
                artifacts.appendingPathComponent("staticAnalysis.stdout.log")
            )
            .contains("child-success-token"))
        #expect(
            try readPipelineCLIText(
                artifacts.appendingPathComponent("staticAnalysis.stderr.log")
            )
            .contains("child-error-token"))
        let artifactReport = try decodePipelineCLIJSON(
            PipelineCLIObservedReport.self,
            from: readPipelineCLIText(artifacts.appendingPathComponent("report.json")))
        #expect(artifactReport == report)
    }
}
