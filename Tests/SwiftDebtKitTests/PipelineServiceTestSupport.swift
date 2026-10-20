import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

func makeConfiguration(
    schemaVersion: Int = 1,
    commands: [PipelineCommand] = []
) -> PipelineConfiguration {
    PipelineConfiguration(
        schemaVersion: schemaVersion,
        context: PipelineContext(risk: .low, trigger: .pullRequest, impact: .known),
        commands: commands
    )
}

func shell(
    _ check: PipelineCheck,
    _ script: String,
    trailing: [String] = []
) -> PipelineCommand {
    PipelineCommand(
        check: check,
        executable: "/bin/sh",
        arguments: ["-c", script, "pipeline"] + trailing,
        timeoutSeconds: 2
    )
}

func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-debt-pipeline-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

func makeInvalidTimeoutConfiguration(_ timeoutSeconds: Double) -> PipelineConfiguration {
    makeConfiguration(commands: [
        PipelineCommand(check: .unit, executable: "/bin/sh", timeoutSeconds: timeoutSeconds)
    ])
}

func status(
    of check: PipelineCheck,
    in report: PipelineRunReport
) -> PipelineCheckStatus? {
    report.evaluation.results.first { $0.check == check }?.status
}

func text(_ name: String, in directory: URL) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
}

func expectPipelineEvidence(
    report: PipelineRunReport,
    configuration: PipelineConfiguration,
    artifacts: URL
) throws {
    #expect(
        [
            status(of: .staticAnalysis, in: report),
            status(of: .architecture, in: report),
            status(of: .unit, in: report),
            status(of: .integration, in: report),
        ] == [.passed, .failed, .passed, .unavailable])
    #expect(report.evaluation.verdict == .failed)
    #expect(
        [
            try text("staticAnalysis.stdout.log", in: artifacts),
            try text("staticAnalysis.stderr.log", in: artifacts),
            try text("architecture.stderr.log", in: artifacts),
            try text("unit.stdout.log", in: artifacts),
        ] == [
            "standard output",
            "standard error",
            "architecture failed",
            "continued after failure",
        ])
    #expect(
        !FileManager.default.fileExists(
            atPath: artifacts.appendingPathComponent("integration.stdout.log").path))

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    #expect(
        try encoder.encode(configuration)
            == Data(contentsOf: artifacts.appendingPathComponent("configuration.json")))
    let persisted = try JSONDecoder().decode(
        PipelineRunReport.self,
        from: Data(contentsOf: artifacts.appendingPathComponent("report.json"))
    )
    #expect(persisted.evaluation.verdict == report.evaluation.verdict)
    #expect(persisted.evaluation.results == report.evaluation.results)
}
