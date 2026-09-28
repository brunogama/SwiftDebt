import Foundation
import SwiftDebtCore
import SwiftDebtKit

struct DebtValidationOptions: Sendable {
    let maxScore: Double
    let quiet: Bool
}

extension CLIOptions {
    func parseDebt(_ input: [String]) throws -> CLIAction {
        guard let command = input.first else {
            throw CLIError("Missing debt command: analyze or validate")
        }
        let arguments = Array(input.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] || arguments == ["help"] { return .help }
        switch command {
        case "analyze":
            let parsed = try parseDebtArguments(arguments, validates: false)
            return .analyze(parsed.request, interactiveDebt: false)
        case "validate":
            let parsed = try parseDebtArguments(arguments, validates: true)
            guard let validation = parsed.validation else {
                throw CLIError("Missing validation options")
            }
            return .debtValidate(parsed.request, validation)
        case "--help", "-h", "help":
            return .help
        default:
            throw CLIError("Unknown debt command: \(command)")
        }
    }

    private func parseDebtArguments(_ arguments: [String], validates: Bool) throws
        -> DebtParsedArguments
    {
        let parsed = try parseRawDebtArguments(arguments, validates: validates)
        let values = parsed.values
        let categories = parsed.repeated["--category", default: []]
        let levels = try parsed.repeated["--level", default: []].map { value in
            guard let level = DebtAggregationLevel(rawValue: value) else {
                throw CLIError("Invalid debt level: \(value)")
            }
            return level
        }
        let path = parsed.paths.first
        let quiet = parsed.flags.contains("--quiet")
        if quiet, !validates { throw CLIError("--quiet is only valid for debt validate") }
        if values["--manifest"] != nil && path != nil {
            throw CLIError("Use either an input path or --manifest, not both")
        }
        if !validates, values["--max-score"] != nil {
            throw CLIError("--max-score is only valid for debt validate")
        }
        return try buildDebtArguments(
            parsed: parsed, validates: validates, levels: levels, categories: categories)
    }

    private func parseRawDebtArguments(
        _ arguments: [String], validates: Bool
    ) throws -> ParsedCLIArguments {
        let valuedOptions: Set<String> = [
            "--config", "--format", "--output", "--profile-output", "--jobs", "--manifest",
            "--stamp", "--exclude",
            "--lcov", "--coverage", "--preset", "--aggregation", "--top", "--head", "--tail",
            "--min-score",
            "--min-priority", "--category", "--level", "--max-score", "--debt-reference-time",
            "--max-file-bytes", "--git-executable",
        ]
        let parsed = try parseArguments(
            arguments,
            schema: CLIArgumentSchema(
                valuedOptions: valuedOptions,
                repeatableOptions: ["--exclude", "--category", "--level"],
                flags: ["--quiet", "--plugin-evidence-limitations"],
                flagValues: [
                    "--plain": ("--format", "plain"),
                    "--compact": ("--format", "compact"),
                ],
                aliases: ["--coverage": "--lcov"]))
        if parsed.requestedHelp {
            throw CLIError("Use 'swift-debt debt \(validates ? "validate" : "analyze") --help'")
        }
        guard parsed.paths.count <= 1 else { throw CLIError("Only one input path is accepted") }
        return parsed
    }

    private func buildDebtArguments(
        parsed: ParsedCLIArguments, validates: Bool,
        levels: [DebtAggregationLevel], categories: [String]
    ) throws -> DebtParsedArguments {
        let values = parsed.values
        let exclusions = parsed.repeated["--exclude", default: []]
        let path = parsed.paths.first
        let quiet = parsed.flags.contains("--quiet")
        let pluginEvidenceLimitations = parsed.flags.contains("--plugin-evidence-limitations")
        let format = try debtFormat(values["--format"], validates: validates)
        let jobs = try optionalInteger(values["--jobs"], named: "--jobs", range: 1...64)
        let maximumFileBytes = try optionalInteger(
            values["--max-file-bytes"], named: "--max-file-bytes", range: 1...Int.max)
        let options = try debtAnalysisOptions(
            values: values, categories: categories, levels: levels)
        let request = AnalysisRequest(
            path: path ?? ".", manifestPath: values["--manifest"],
            configurationPath: values["--config"], outputPath: values["--output"],
            stampPath: values["--stamp"], format: format, jobs: jobs, exclude: exclusions,
            debtAnalysisOptions: options, enableDebtAnalysis: true, lcovPath: values["--lcov"],
            debtReferenceTime: try parseDebtReferenceTime(values["--debt-reference-time"]),
            gitExecutablePath: try parseGitExecutablePath(values["--git-executable"]),
            profileOutputPath: values["--profile-output"],
            pluginEvidenceLimitations: pluginEvidenceLimitations,
            maximumFileBytes: maximumFileBytes)
        let maxScore = try optionalScore(values["--max-score"], named: "--max-score")
        if validates, maxScore == nil {
            throw CLIError("Missing required --max-score for debt validate")
        }
        let validation = maxScore.map { DebtValidationOptions(maxScore: $0, quiet: quiet) }
        return DebtParsedArguments(request: request, validation: validation)
    }

    private func debtAnalysisOptions(
        values: [String: String], categories: [String], levels: [DebtAggregationLevel]
    ) throws -> DebtAnalysisOptions? {
        let preset = try optionalRaw(
            DebtAnalysisPreset.self, values["--preset"], named: "debt preset")
        let aggregation = try optionalRaw(
            DebtAggregationStrategy.self, values["--aggregation"], named: "debt aggregation")
        let minPriority = try optionalRaw(
            Priority.self, values["--min-priority"], named: "minimum priority")
        let minScore = try optionalScore(values["--min-score"], named: "--min-score")
        let top = try optionalInteger(values["--top"], named: "--top", range: 0...Int.max)
        let head = try optionalInteger(values["--head"], named: "--head", range: 0...Int.max)
        let tail = try optionalInteger(values["--tail"], named: "--tail", range: 0...Int.max)
        let hasDebtOverrides =
            preset != nil || aggregation != nil || minScore != nil || minPriority != nil
            || !categories.isEmpty || !levels.isEmpty || top != nil || head != nil || tail != nil
        let options =
            hasDebtOverrides
            ? DebtAnalysisOptions(
                preset: preset ?? .balanced,
                aggregationStrategy: aggregation ?? .file,
                minScore: minScore,
                minPriority: minPriority,
                categories: categories,
                levels: levels,
                top: top,
                head: head,
                tail: tail
            )
            : nil
        return options
    }

}

private struct DebtParsedArguments {
    let request: AnalysisRequest
    let validation: DebtValidationOptions?
}
