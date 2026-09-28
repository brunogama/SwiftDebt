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

    func parse(_ input: [String]) throws -> CLIAction {
        if input == ["--help"] || input == ["-h"] || input == ["help"] { return .help }
        if input == ["--version"] || input == ["version"] { return .version }
        let arguments = input
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
        return try parseAnalyze(arguments)
    }

    private func parseAnalyze(_ input: [String]) throws -> CLIAction {
        var arguments = input
        if arguments.first == "analyze" { arguments.removeFirst() }
        let valuedOptions: Set<String> = [
            "--config", "--format", "--output", "--profile-output", "--type-scope", "--scoring",
            "--jobs",
            "--manifest", "--stamp", "--exclude", "--threshold", "--lcov", "--debt-reference-time",
            "--max-file-bytes", "--git-executable",
        ]
        let parsed = try parseArguments(
            arguments,
            schema: CLIArgumentSchema(
                valuedOptions: valuedOptions,
                repeatableOptions: ["--exclude", "--threshold"],
                flags: [
                    "--fail-on-violation", "--strict", "--interactive-debt",
                    "--plugin-evidence-limitations",
                ]))
        return try analyzeAction(parsed)
    }

    private func analyzeAction(_ parsed: ParsedCLIArguments) throws -> CLIAction {
        if parsed.requestedHelp { return .help }
        guard parsed.paths.count <= 1 else { throw CLIError("Only one input path is accepted") }
        let values = parsed.values
        let exclusions = parsed.repeated["--exclude", default: []]
        let thresholds = try parseThresholds(parsed.repeated["--threshold", default: []])
        let path = parsed.paths.first
        let fail = parsed.flags.contains("--fail-on-violation")
        let strict = parsed.flags.contains("--strict")
        let interactiveDebt = parsed.flags.contains("--interactive-debt")
        let pluginEvidenceLimitations = parsed.flags.contains("--plugin-evidence-limitations")
        if values["--manifest"] != nil && path != nil {
            throw CLIError("Use either an input path or --manifest, not both")
        }
        let format: ReportFormat? = try decode(values["--format"], named: "format")
        if interactiveDebt {
            if values["--output"] != nil {
                throw CLIError("Use either --interactive-debt or --output, not both")
            }
            if let format, !format.isDebtReportFormat {
                throw CLIError(
                    "--interactive-debt requires a debt report format when --format is provided")
            }
        }
        let scope: TypeScope? = try decode(values["--type-scope"], named: "type scope")
        let scoring: ScoringMode? = try decode(values["--scoring"], named: "scoring mode")
        let jobs = try analyzeInteger(
            values["--jobs"], range: 1...64,
            error: "jobs must be an integer from 1 to 64")
        let maximumFileBytes = try analyzeInteger(
            values["--max-file-bytes"], range: 1...Int.max,
            error: "max-file-bytes must be a positive integer")
        let settings = AnalyzeSettings(
            values: values, exclusions: exclusions, thresholds: thresholds, path: path,
            fail: fail, strict: strict, interactiveDebt: interactiveDebt,
            pluginEvidenceLimitations: pluginEvidenceLimitations, format: format, scope: scope,
            scoring: scoring, jobs: jobs, maximumFileBytes: maximumFileBytes)
        return .analyze(try analysisRequest(settings), interactiveDebt: interactiveDebt)
    }

    private func analyzeInteger(
        _ value: String?, range: ClosedRange<Int>, error message: String
    ) throws -> Int? {
        guard let value else { return nil }
        guard let number = Int(value), range.contains(number) else { throw CLIError(message) }
        return number
    }

    private func analysisRequest(_ settings: AnalyzeSettings) throws -> AnalysisRequest {
        let values = settings.values
        return AnalysisRequest(
            path: settings.path ?? ".", manifestPath: values["--manifest"],
            configurationPath: values["--config"], outputPath: values["--output"],
            stampPath: values["--stamp"], typeScope: settings.scope, scoring: settings.scoring,
            format: settings.format ?? (settings.interactiveDebt ? .debtCompact : nil),
            jobs: settings.jobs, failOnViolation: settings.fail,
            strictSyntax: settings.strict, exclude: settings.exclusions,
            thresholds: settings.thresholds,
            debtAnalysisOptions: settings.interactiveDebt ? DebtAnalysisOptions() : nil,
            lcovPath: values["--lcov"],
            debtReferenceTime: try parseDebtReferenceTime(values["--debt-reference-time"]),
            gitExecutablePath: try parseGitExecutablePath(values["--git-executable"]),
            profileOutputPath: values["--profile-output"],
            pluginEvidenceLimitations: settings.pluginEvidenceLimitations,
            maximumFileBytes: settings.maximumFileBytes)
    }

    private func parseThresholds(_ values: [String]) throws -> [Metric: Int] {
        var thresholds: [Metric: Int] = [:]
        for value in values {
            let pair = value.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2, let metric = Metric(rawValue: pair[0].uppercased()),
                let number = Int(pair[1]), number >= 0
            else {
                throw CLIError("Invalid threshold \(value); expected a metric such as CCF=20")
            }
            guard thresholds[metric] == nil else {
                throw CLIError("Duplicate threshold: \(metric.rawValue)")
            }
            thresholds[metric] = number
        }
        return thresholds
    }

}

private struct AnalyzeSettings {
    let values: [String: String]
    let exclusions: [String]
    let thresholds: [Metric: Int]
    let path: String?
    let fail: Bool
    let strict: Bool
    let interactiveDebt: Bool
    let pluginEvidenceLimitations: Bool
    let format: ReportFormat?
    let scope: TypeScope?
    let scoring: ScoringMode?
    let jobs: Int?
    let maximumFileBytes: Int?
}

struct DebtReportPairArguments {
    let beforePath: String
    let afterPath: String
    let outputPath: String?
    let threshold: Double?
}
