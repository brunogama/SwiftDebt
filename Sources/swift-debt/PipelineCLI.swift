import Foundation
import SwiftDebtKit

enum PipelineCLIRequest {
    case plan(configurationPath: String)
    case run(configurationPath: String, artifactsPath: String)
}

extension CLIOptions {
    func parsePipeline(_ arguments: [String]) throws -> CLIAction {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        guard let operation = arguments.first, ["plan", "run"].contains(operation) else {
            throw CLIError("Expected pipeline plan or pipeline run")
        }
        let parsed = try parseArguments(
            Array(arguments.dropFirst()),
            schema: CLIArgumentSchema(
                valuedOptions: operation == "run" ? ["--artifacts"] : []))
        if parsed.requestedHelp { return .help }
        guard parsed.paths.count == 1 else {
            throw CLIError("Expected one pipeline configuration path")
        }
        if operation == "plan" {
            return .pipeline(.plan(configurationPath: parsed.paths[0]))
        }
        guard let artifacts = parsed.values["--artifacts"], !artifacts.isEmpty else {
            throw CLIError("pipeline run requires --artifacts NEW_DIRECTORY")
        }
        return .pipeline(
            .run(configurationPath: parsed.paths[0], artifactsPath: artifacts))
    }
}

enum PipelineCLI {
    static func run(_ request: PipelineCLIRequest) throws -> (output: String, exitStatus: Int32) {
        switch request {
        case .plan(let path):
            let configuration = try load(path)
            let plan = try PipelineService().plan(configuration: configuration)
            return (try render(plan), 0)
        case .run(let path, let artifacts):
            let configurationURL = URL(fileURLWithPath: path).standardizedFileURL
            let configuration = try load(path)
            let report = try PipelineService().run(
                configuration: configuration,
                workingDirectory: configurationURL.deletingLastPathComponent(),
                artifactsDirectory: URL(fileURLWithPath: artifacts).standardizedFileURL)
            return (try render(report), report.evaluation.exitStatus)
        }
    }

    private static func load(_ path: String) throws -> PipelineConfiguration {
        try JSONDecoder().decode(
            PipelineConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    private static func render(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let json = String(bytes: try encoder.encode(value), encoding: .utf8) else {
            throw CLIError("Could not encode pipeline output as UTF-8")
        }
        return json + "\n"
    }
}
