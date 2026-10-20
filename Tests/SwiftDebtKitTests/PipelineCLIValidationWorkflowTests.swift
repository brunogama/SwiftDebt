import Foundation
import Testing

@Suite("Pipeline CLI input and artifact validation")
struct PipelineCLIValidationWorkflowTests {
    @Test("An unknown run flag exits two before commands or artifacts")
    func invalidFlagCreatesNoArtifacts() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = root.appendingPathComponent("pipeline.json")
        try writePipelineCLIConfiguration(
            at: configuration,
            commands: [
                PipelineCLICommandFixture(
                    check: "staticAnalysis",
                    arguments: ["-c", "printf ran > invalid-flag-command-ran"])
            ])

        let result = try runSwiftDebt(
            [
                "pipeline", "run", "pipeline.json", "--artifacts", "artifacts",
                "--unexpected",
            ],
            currentDirectory: root)

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.contains("Unknown option: --unexpected"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("artifacts").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("invalid-flag-command-ran").path))
    }

    @Test("An unsupported configuration schema exits two before commands or artifacts")
    func invalidSchemaCreatesNoArtifacts() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = root.appendingPathComponent("pipeline.json")
        try writePipelineCLIConfiguration(
            at: configuration,
            schemaVersion: 2,
            commands: [
                PipelineCLICommandFixture(
                    check: "staticAnalysis",
                    arguments: ["-c", "printf ran > invalid-schema-command-ran"])
            ])

        let result = try runSwiftDebt(
            ["pipeline", "run", "pipeline.json", "--artifacts", "artifacts"],
            currentDirectory: root)

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.lowercased().contains("schema"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("artifacts").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("invalid-schema-command-ran").path))
    }

    @Test("An existing artifacts directory is rejected without changing its output")
    func reusedArtifactsArePreserved() throws {
        let root = try makePipelineCLITemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = root.appendingPathComponent("pipeline.json")
        try writePipelineCLIConfiguration(
            at: configuration,
            commands: [
                PipelineCLICommandFixture(
                    check: "staticAnalysis",
                    arguments: ["-c", "printf ran > reused-artifacts-command-ran"])
            ])
        let artifacts = root.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let report = artifacts.appendingPathComponent("report.json")
        let log = artifacts.appendingPathComponent("staticAnalysis.stdout.log")
        try "preexisting report\n".write(to: report, atomically: true, encoding: .utf8)
        try "preexisting stdout\n".write(to: log, atomically: true, encoding: .utf8)

        let result = try runSwiftDebt(
            ["pipeline", "run", "pipeline.json", "--artifacts", "artifacts"],
            currentDirectory: root)

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.lowercased().contains("already exists"))
        #expect(try readPipelineCLIText(report) == "preexisting report\n")
        #expect(try readPipelineCLIText(log) == "preexisting stdout\n")
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: artifacts.path).sorted()
                == ["report.json", "staticAnalysis.stdout.log"])
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("reused-artifacts-command-ran").path))
    }
}
