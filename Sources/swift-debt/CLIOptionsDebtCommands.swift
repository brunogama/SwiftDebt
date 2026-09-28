import Foundation
import SwiftDebtCore
import SwiftDebtKit

extension CLIOptions {
    func isDebtNamespace(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        switch command {
        case "analyze", "validate", "--help", "-h", "help":
            return true
        default:
            return false
        }
    }

    func parseCompare(_ arguments: [String]) throws -> CLIAction {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        let parsed = try parseDebtReportPair(arguments, allowsThreshold: false)
        return .compare(
            DebtComparisonRequest(
                beforePath: parsed.beforePath,
                afterPath: parsed.afterPath,
                outputPath: parsed.outputPath
            )
        )
    }

    func parseValidateImprovement(_ arguments: [String]) throws -> CLIAction {
        if arguments == ["--help"] || arguments == ["-h"] { return .help }
        let parsed = try parseDebtReportPair(arguments, allowsThreshold: true)
        return .validateImprovement(
            DebtValidationRequest(
                beforePath: parsed.beforePath,
                afterPath: parsed.afterPath,
                minimumImprovement: parsed.threshold ?? 0,
                outputPath: parsed.outputPath
            )
        )
    }

    func parseDebtReportPair(
        _ arguments: [String],
        allowsThreshold: Bool
    ) throws -> DebtReportPairArguments {
        let valuedOptions: Set<String> =
            allowsThreshold ? ["--output", "--threshold"] : ["--output"]
        let parsed = try parseArguments(
            arguments, schema: CLIArgumentSchema(valuedOptions: valuedOptions))
        if parsed.requestedHelp { throw CLIError("Unexpected help option") }
        guard parsed.paths.count == 2 else {
            throw CLIError("Expected before and after debt report paths")
        }
        var threshold: Double?
        if let value = parsed.values["--threshold"] {
            guard let parsed = Double(value), parsed >= 0 else {
                throw CLIError("threshold must be a nonnegative number")
            }
            threshold = parsed
        }
        return DebtReportPairArguments(
            beforePath: parsed.paths[0],
            afterPath: parsed.paths[1],
            outputPath: parsed.values["--output"],
            threshold: threshold
        )
    }

    func parseExplainCoverage(_ arguments: [String]) throws -> CLIAction {
        let valuedOptions: Set<String> = [
            "--config", "--manifest", "--exclude", "--lcov", "--max-file-bytes",
        ]
        let parsed = try parseArguments(
            arguments,
            schema: CLIArgumentSchema(
                valuedOptions: valuedOptions, repeatableOptions: ["--exclude"]))
        if parsed.requestedHelp { return .help }
        guard parsed.paths.count <= 1 else { throw CLIError("Only one input path is accepted") }
        let values = parsed.values
        let path = parsed.paths.first
        guard let lcovPath = values["--lcov"] else {
            throw CLIError("Missing required --lcov for explain coverage")
        }
        var maximumFileBytes: Int?
        if let value = values["--max-file-bytes"] {
            guard let count = Int(value), count > 0 else {
                throw CLIError("max-file-bytes must be a positive integer")
            }
            maximumFileBytes = count
        }
        if values["--manifest"] != nil && path != nil {
            throw CLIError("Use either an input path or --manifest, not both")
        }
        return .explainCoverage(
            CoverageExplanationRequest(
                path: path ?? ".",
                lcovPath: lcovPath,
                manifestPath: values["--manifest"],
                configurationPath: values["--config"],
                exclude: parsed.repeated["--exclude", default: []],
                maximumFileBytes: maximumFileBytes
            )
        )
    }

    func decode<T: RawRepresentable>(_ value: String?, named name: String) throws -> T?
    where T.RawValue == String {
        guard let value else { return nil }
        guard let result = T(rawValue: value) else { throw CLIError("Invalid \(name): \(value)") }
        return result
    }

    func parseDebtReferenceTime(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        guard let date = DebtReferenceTimeParser.parse(value) else {
            throw CLIError(
                "Invalid ISO-8601 timestamp for --debt-reference-time: \(value); expected \(DebtReferenceTimeParser.example)"
            )
        }
        return date
    }
}
