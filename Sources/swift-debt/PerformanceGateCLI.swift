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
        var paths: [String] = []
        var values: [String: String] = [:]
        var index = 0
        let options = Set([
            "--name",
            "--max-wall-clock-regression",
            "--max-wall-clock-regression-seconds",
            "--max-peak-memory-regression",
            "--output",
        ])
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if argument.hasPrefix("--") {
                guard options.contains(argument) else { throw CLIError("Unknown option: \(argument)") }
                guard index < arguments.count else { throw CLIError("Missing value for \(argument)") }
                guard values[argument] == nil else { throw CLIError("Duplicate option: \(argument)") }
                values[argument] = arguments[index]
                index += 1
            } else {
                paths.append(argument)
            }
        }
        guard paths.count == 2 else {
            throw CLIError("Expected baseline and candidate benchmark result paths")
        }
        let name = values["--name"] ?? "performance"
        let wallClock = try performanceLimit(
            values["--max-wall-clock-regression"],
            option: "--max-wall-clock-regression"
        )
        let wallClockSeconds = try performanceLimit(
            values["--max-wall-clock-regression-seconds"] ?? "0",
            option: "--max-wall-clock-regression-seconds"
        )
        let peakMemory = try performanceLimit(
            values["--max-peak-memory-regression"],
            option: "--max-peak-memory-regression"
        )
        return .performanceGate(
            PerformanceGateRequest(
                baselinePath: paths[0],
                candidatePath: paths[1],
                outputPath: values["--output"],
                budget: PerformanceRegressionBudget(
                    name: name,
                    maximumWallClockRegressionPercent: wallClock,
                    maximumPeakMemoryRegressionPercent: peakMemory,
                    maximumWallClockRegressionSeconds: wallClockSeconds
                )
            )
        )
    }

    private func performanceLimit(_ value: String?, option: String) throws -> Double {
        guard let value, let result = Double(value), result >= 0, result.isFinite else {
            throw CLIError("\(option) must be a nonnegative finite number")
        }
        return result
    }
}

enum PerformanceGateCLI {
    static func run(_ request: PerformanceGateRequest) throws -> (output: String, exitStatus: Int32) {
        let baselineURL = URL(fileURLWithPath: request.baselinePath).standardizedFileURL
        let candidateURL = URL(fileURLWithPath: request.candidatePath).standardizedFileURL
        let decoder = JSONDecoder()
        let baseline = try decoder.decode(PerformanceBenchmarkResult.self, from: Data(contentsOf: baselineURL))
        let candidate = try decoder.decode(PerformanceBenchmarkResult.self, from: Data(contentsOf: candidateURL))
        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline,
            candidate: candidate,
            budget: request.budget
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let rendered = String(decoding: try encoder.encode(evaluation), as: UTF8.self) + "\n"
        if let outputPath = request.outputPath {
            let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL
            guard outputURL != baselineURL, outputURL != candidateURL else {
                throw CLIError("Performance gate output must not overwrite an input")
            }
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(rendered.utf8).write(to: outputURL, options: .atomic)
            return ("", evaluation.passed ? 0 : 1)
        }
        return (rendered, evaluation.passed ? 0 : 1)
    }
}
