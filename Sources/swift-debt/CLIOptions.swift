import Foundation
import SwiftDebtCore
import SwiftDebtKit

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

enum CLIAction {
    case help
    case version
    case analyze(AnalysisRequest, interactiveDebt: Bool)
    case debtValidate(AnalysisRequest, DebtValidationOptions)
    case compare(DebtComparisonRequest)
    case validateImprovement(DebtValidationRequest)
    case explainCoverage(CoverageExplanationRequest)
    case performanceGate(PerformanceGateRequest)
}

struct CLIOptions {
    static let help = """
        OVERVIEW: SwiftDebt - Swift source metrics based on the SCMA paper.

        USAGE: swift-debt analyze [path] [options]
               swift-debt debt analyze [path] [options]
               swift-debt debt validate [path] --max-score SCORE [options]
               swift-debt compare BEFORE_JSON AFTER_JSON [--output PATH]
               swift-debt validate-improvement BEFORE_JSON AFTER_JSON [--threshold SCORE] [--output PATH]
               swift-debt explain coverage [path] --lcov PATH [options]
               swift-debt performance-gate BASELINE_JSON CANDIDATE_JSON [options]
               swift-debt --help
               swift-debt --version

        OPTIONS:
          --config PATH                  JSON configuration (default: <root>/.swift-debt.json).
          --format FORMAT                text, json, csv, html, diagnostics (default: text),
                                         plus debt-json, debt-markdown, debt-dot,
                                         debt-text, debt-compact, debtmap-json,
                                         debt-dashboard.
          --interactive-debt             Open ranked debt explorer when terminal supports it.
          --output PATH                  Write a report atomically instead of stdout.
          --profile-output PATH          Write machine-readable phase profiling JSON.
          --name NAME                    Performance budget name.
          --max-wall-clock-regression PERCENT
                                         Maximum accepted wall-clock regression.
          --max-peak-memory-regression PERCENT
                                         Maximum accepted peak-memory regression.
          --threshold SCORE              Required improvement for validate-improvement.
          --type-scope SCOPE             classes (paper scope) or nominals.
          --scoring MODE                 none (default), paper (literal), bounded (clamped),
                                         corrected (clamped, DC ratio = duplicated/total lines).
          --threshold METRIC=INTEGER     Override a diagnostic threshold; repeatable.
          --exclude RELATIVE_PATH        Exclude a relative path prefix; repeatable; no globs.
          --jobs INTEGER                 Bounded parallel parsing, 1...64 (default: CPU count, max 8).
          --max-file-bytes INTEGER       Maximum bytes accepted for each source file.
          --fail-on-violation            Exit 1 when configured thresholds are exceeded.
          --strict                       Exit 2 on any parse error instead of skipping that file.
          --manifest PATH                Explicit JSON source manifest (used by plugins).
          --lcov PATH                    LCOV input for explain coverage or debt evidence.
          --coverage PATH                Alias for --lcov in debt workflows.
          --debt-reference-time TIME     ISO-8601 reference time for Git-history evidence.
          --preset PRESET                Debt preset: strict, balanced, lenient.
          --aggregation MODE             Debt aggregation: none, file, aggregateOnly.
          --top N | --head N | --tail N  Limit ranked debt output deterministically.
          --min-score SCORE              Keep debt items with score at least SCORE.
          --min-priority PRIORITY        Keep debt items at least low, medium, high, critical.
          --category NAME                Keep a debt category; repeatable.
          --level LEVEL                  Keep callable, type, file, or module; repeatable.
          --max-score SCORE              Validate that no debt score exceeds SCORE.
          --quiet                        Suppress validation summary output.
          --stamp PATH                   Internal build-plugin completion marker.
          --                             Treat the remaining argument as a literal path.

        EXIT STATUS: 0 success; 1 opted-in metric or improvement gate failed; 2 input/configuration/analysis error.
        Paper equations are experimental. Undefined scores are not replaced with a passing grade.
        """

    func parse(_ input: [String]) throws -> CLIAction {
        if input == ["--help"] || input == ["-h"] || input == ["help"] { return .help }
        if input == ["--version"] || input == ["version"] { return .version }
        var arguments = input
        if arguments.first == "compare" {
            return try parseCompare(Array(arguments.dropFirst()))
        }
        if arguments.first == "validate-improvement" {
            return try parseValidateImprovement(Array(arguments.dropFirst()))
        }
        if arguments.first == "explain", arguments.dropFirst().first == "coverage" {
            return try parseExplainCoverage(Array(arguments.dropFirst(2)))
        }
        if arguments.first == "performance-gate" {
            return try parsePerformanceGate(Array(arguments.dropFirst()))
        }
        if arguments.first == "debt", isDebtNamespace(Array(arguments.dropFirst())) {
            return try parseDebt(Array(arguments.dropFirst()))
        }
        if arguments.first == "analyze" { arguments.removeFirst() }
        var values: [String: String] = [:]
        var exclusions: [String] = []
        var thresholds: [Metric: Int] = [:]
        var path: String?
        var fail = false
        var strict = false
        var interactiveDebt = false
        var pluginEvidenceLimitations = false
        var literal = false
        var index = 0
        let valuedOptions: Set<String> = [
            "--config", "--format", "--output", "--profile-output", "--type-scope", "--scoring", "--jobs",
            "--manifest", "--stamp", "--exclude", "--threshold", "--lcov", "--debt-reference-time",
            "--max-file-bytes",
        ]
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if !literal && (argument == "--help" || argument == "-h") { return .help }
            if !literal && argument == "--" {
                literal = true
                continue
            }
            if !literal && argument == "--fail-on-violation" {
                guard !fail else { throw CLIError("Duplicate --fail-on-violation") }
                fail = true
                continue
            }
            if !literal && argument == "--strict" {
                guard !strict else { throw CLIError("Duplicate --strict") }
                strict = true
                continue
            }
            if !literal && argument == "--interactive-debt" {
                guard !interactiveDebt else { throw CLIError("Duplicate --interactive-debt") }
                interactiveDebt = true
                continue
            }
            if !literal && argument == "--plugin-evidence-limitations" {
                guard !pluginEvidenceLimitations else { throw CLIError("Duplicate --plugin-evidence-limitations") }
                pluginEvidenceLimitations = true
                continue
            }
            if !literal && argument.hasPrefix("-") {
                let split = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(
                    String.init)
                let key = split[0]
                guard valuedOptions.contains(key) else { throw CLIError("Unknown option: \(key)") }
                let value: String
                if split.count == 2 {
                    value = split[1]
                } else {
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw CLIError("Missing value for \(key)")
                    }
                    value = arguments[index]
                    index += 1
                }
                guard !value.isEmpty else { throw CLIError("Empty value for \(key)") }
                if key == "--exclude" {
                    exclusions.append(value)
                    continue
                }
                if key == "--threshold" {
                    let pair = value.split(separator: "=", maxSplits: 1).map(String.init)
                    guard pair.count == 2, let metric = Metric(rawValue: pair[0].uppercased()),
                        let number = Int(pair[1]), number >= 0
                    else {
                        throw CLIError("Invalid threshold \(value); expected a metric such as CCF=20")
                    }
                    guard thresholds[metric] == nil else { throw CLIError("Duplicate threshold: \(metric.rawValue)") }
                    thresholds[metric] = number
                    continue
                }
                guard values[key] == nil else { throw CLIError("Duplicate option: \(key)") }
                values[key] = value
                continue
            }
            guard path == nil else { throw CLIError("Only one input path is accepted") }
            path = argument
        }
        if values["--manifest"] != nil && path != nil {
            throw CLIError("Use either an input path or --manifest, not both")
        }
        let format: ReportFormat? = try decode(values["--format"], named: "format")
        if interactiveDebt {
            if values["--output"] != nil {
                throw CLIError("Use either --interactive-debt or --output, not both")
            }
            if let format, !format.isDebtReportFormat {
                throw CLIError("--interactive-debt requires a debt report format when --format is provided")
            }
        }
        let scope: TypeScope? = try decode(values["--type-scope"], named: "type scope")
        let scoring: ScoringMode? = try decode(values["--scoring"], named: "scoring mode")
        var jobs: Int?
        if let value = values["--jobs"] {
            guard let count = Int(value), (1...64).contains(count) else {
                throw CLIError("jobs must be an integer from 1 to 64")
            }
            jobs = count
        }
        var maximumFileBytes: Int?
        if let value = values["--max-file-bytes"] {
            guard let count = Int(value), count > 0 else {
                throw CLIError("max-file-bytes must be a positive integer")
            }
            maximumFileBytes = count
        }
        return .analyze(
            AnalysisRequest(
                path: path ?? ".", manifestPath: values["--manifest"], configurationPath: values["--config"],
                outputPath: values["--output"], stampPath: values["--stamp"], typeScope: scope,
                scoring: scoring, format: format ?? (interactiveDebt ? .debtCompact : nil), jobs: jobs,
                failOnViolation: fail, strictSyntax: strict, exclude: exclusions, thresholds: thresholds,
                debtAnalysisOptions: interactiveDebt ? DebtAnalysisOptions() : nil,
                lcovPath: values["--lcov"],
                debtReferenceTime: try parseDebtReferenceTime(values["--debt-reference-time"]),
                profileOutputPath: values["--profile-output"],
                pluginEvidenceLimitations: pluginEvidenceLimitations,
                maximumFileBytes: maximumFileBytes
            ),
            interactiveDebt: interactiveDebt
        )
    }

    private func isDebtNamespace(_ arguments: [String]) -> Bool {
        guard let command = arguments.first else { return false }
        switch command {
        case "analyze", "validate", "--help", "-h", "help":
            return true
        default:
            return false
        }
    }

    private func parseCompare(_ arguments: [String]) throws -> CLIAction {
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

    private func parseValidateImprovement(_ arguments: [String]) throws -> CLIAction {
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

    private func parseDebtReportPair(
        _ arguments: [String],
        allowsThreshold: Bool
    ) throws -> (beforePath: String, afterPath: String, outputPath: String?, threshold: Double?) {
        var values: [String: String] = [:]
        var paths: [String] = []
        var literal = false
        var index = 0
        let valuedOptions: Set<String> = allowsThreshold ? ["--output", "--threshold"] : ["--output"]
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if !literal && (argument == "--help" || argument == "-h") { throw CLIError("Unexpected help option") }
            if !literal && argument == "--" {
                literal = true
                continue
            }
            if !literal && argument.hasPrefix("-") {
                let split = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(
                    String.init)
                let key = split[0]
                guard valuedOptions.contains(key) else { throw CLIError("Unknown option: \(key)") }
                let value: String
                if split.count == 2 {
                    value = split[1]
                } else {
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw CLIError("Missing value for \(key)")
                    }
                    value = arguments[index]
                    index += 1
                }
                guard !value.isEmpty else { throw CLIError("Empty value for \(key)") }
                guard values[key] == nil else { throw CLIError("Duplicate option: \(key)") }
                values[key] = value
                continue
            }
            paths.append(argument)
        }
        guard paths.count == 2 else { throw CLIError("Expected before and after debt report paths") }
        var threshold: Double?
        if let value = values["--threshold"] {
            guard let parsed = Double(value), parsed >= 0 else {
                throw CLIError("threshold must be a nonnegative number")
            }
            threshold = parsed
        }
        return (paths[0], paths[1], values["--output"], threshold)
    }

    private func parseExplainCoverage(_ arguments: [String]) throws -> CLIAction {
        var values: [String: String] = [:]
        var exclusions: [String] = []
        var path: String?
        var literal = false
        var index = 0
        let valuedOptions: Set<String> = ["--config", "--manifest", "--exclude", "--lcov", "--max-file-bytes"]
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if !literal && (argument == "--help" || argument == "-h") { return .help }
            if !literal && argument == "--" {
                literal = true
                continue
            }
            if !literal && argument.hasPrefix("-") {
                let split = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(
                    String.init)
                let key = split[0]
                guard valuedOptions.contains(key) else { throw CLIError("Unknown option: \(key)") }
                let value: String
                if split.count == 2 {
                    value = split[1]
                } else {
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw CLIError("Missing value for \(key)")
                    }
                    value = arguments[index]
                    index += 1
                }
                guard !value.isEmpty else { throw CLIError("Empty value for \(key)") }
                if key == "--exclude" {
                    exclusions.append(value)
                    continue
                }
                guard values[key] == nil else { throw CLIError("Duplicate option: \(key)") }
                values[key] = value
                continue
            }
            guard path == nil else { throw CLIError("Only one input path is accepted") }
            path = argument
        }
        guard let lcovPath = values["--lcov"] else { throw CLIError("Missing required --lcov for explain coverage") }
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
                exclude: exclusions,
                maximumFileBytes: maximumFileBytes
            )
        )
    }

    private func decode<T: RawRepresentable>(_ value: String?, named name: String) throws -> T?
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
