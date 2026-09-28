import Foundation
import SwiftDebtCore

struct PerformanceGateRequest: Sendable {
    let baselinePath: String
    let candidatePath: String
    let outputPath: String?
    let budget: PerformanceRegressionBudget
}

extension CLIOptions {
    func parsePerformanceGate(_ arguments: [String]) throws -> CLIAction {
        let options = Set([
            "--name",
            "--max-wall-clock-regression",
            "--max-peak-memory-regression",
            "--output",
        ])
        let parsed = try parseArguments(
            arguments, schema: CLIArgumentSchema(valuedOptions: options))
        guard parsed.paths.count == 2 else {
            throw CLIError("Expected baseline and candidate benchmark result paths")
        }
        let values = parsed.values
        let name = values["--name"] ?? "performance"
        let wallClock = try performancePercentage(
            values["--max-wall-clock-regression"],
            option: "--max-wall-clock-regression"
        )
        let peakMemory = try performancePercentage(
            values["--max-peak-memory-regression"],
            option: "--max-peak-memory-regression"
        )
        return .performanceGate(
            PerformanceGateRequest(
                baselinePath: parsed.paths[0],
                candidatePath: parsed.paths[1],
                outputPath: values["--output"],
                budget: PerformanceRegressionBudget(
                    name: name,
                    maximumWallClockRegressionPercent: wallClock,
                    maximumPeakMemoryRegressionPercent: peakMemory
                )
            )
        )
    }

    private func performancePercentage(_ value: String?, option: String) throws -> Double {
        guard let value, let result = Double(value), result >= 0, result.isFinite else {
            throw CLIError("\(option) must be a nonnegative finite number")
        }
        return result
    }
}

enum PerformanceGateCLI {
    static func run(_ request: PerformanceGateRequest) throws -> (output: String, exitStatus: Int32)
    {
        let baselineURL = URL(fileURLWithPath: request.baselinePath).standardizedFileURL
        let candidateURL = URL(fileURLWithPath: request.candidatePath).standardizedFileURL
        let decoder = JSONDecoder()
        let baseline = try decoder.decode(
            PerformanceBenchmarkResult.self, from: Data(contentsOf: baselineURL))
        let candidate = try decoder.decode(
            PerformanceBenchmarkResult.self, from: Data(contentsOf: candidateURL))
        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline,
            candidate: candidate,
            budget: request.budget
        )
        let rendered = try render(evaluation)
        guard let outputPath = request.outputPath else {
            return (rendered, evaluation.passed ? 0 : 1)
        }
        try write(
            rendered, to: outputPath, avoiding: [baselineURL, candidateURL])
        return ("", evaluation.passed ? 0 : 1)
    }

    private static func render(_ evaluation: PerformanceBudgetEvaluation) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(evaluation)
        guard let json = String(bytes: encoded, encoding: .utf8) else {
            throw CLIError("Performance gate result is not valid UTF-8")
        }
        return json + "\n"
    }

    private static func write(_ output: String, to path: String, avoiding inputs: [URL]) throws {
        let outputURL = URL(fileURLWithPath: path).standardizedFileURL
        guard !inputs.contains(outputURL) else {
            throw CLIError("Performance gate output must not overwrite an input")
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(output.utf8).write(to: outputURL, options: .atomic)
    }
}
