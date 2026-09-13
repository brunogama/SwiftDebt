import Foundation
import SCMACore
import SCMAKit

struct DebtValidationOptions: Sendable {
    let maxScore: Double
    let quiet: Bool
}

extension CLIOptions {
    func parseDebt(_ input: [String]) throws -> CLIAction {
        guard let command = input.first else { throw CLIError("Missing debt command: analyze or validate") }
        let arguments = Array(input.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] || arguments == ["help"] { return .help }
        switch command {
        case "analyze":
            let parsed = try parseDebtArguments(arguments, validates: false)
            return .analyze(parsed.request)
        case "validate":
            let parsed = try parseDebtArguments(arguments, validates: true)
            guard let validation = parsed.validation else { throw CLIError("Missing validation options") }
            return .debtValidate(parsed.request, validation)
        case "--help", "-h", "help":
            return .help
        default:
            throw CLIError("Unknown debt command: \(command)")
        }
    }

    private func parseDebtArguments(_ arguments: [String], validates: Bool) throws -> DebtParsedArguments {
        var values: [String: String] = [:]
        var exclusions: [String] = []
        var categories: [String] = []
        var levels: [DebtAggregationLevel] = []
        var path: String?
        var literal = false
        var quiet = false
        var index = 0
        let valuedOptions: Set<String> = [
            "--config", "--format", "--output", "--jobs", "--manifest", "--stamp", "--exclude", "--lcov",
            "--coverage", "--preset", "--aggregation", "--top", "--head", "--tail", "--min-score",
            "--min-priority", "--category", "--level", "--max-score",
        ]
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if !literal && (argument == "--help" || argument == "-h") { throw CLIError("Use 'scma debt \(validates ? "validate" : "analyze") --help'") }
            if !literal && argument == "--" {
                literal = true
                continue
            }
            if !literal && argument == "--plain" {
                try setUnique(&values, key: "--format", value: "plain")
                continue
            }
            if !literal && argument == "--compact" {
                try setUnique(&values, key: "--format", value: "compact")
                continue
            }
            if !literal && argument == "--quiet" {
                guard validates else { throw CLIError("--quiet is only valid for debt validate") }
                guard !quiet else { throw CLIError("Duplicate --quiet") }
                quiet = true
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
                switch key {
                case "--exclude":
                    exclusions.append(value)
                case "--coverage":
                    try setUnique(&values, key: "--lcov", value: value)
                case "--category":
                    categories.append(value)
                case "--level":
                    guard let level = DebtAggregationLevel(rawValue: value) else {
                        throw CLIError("Invalid debt level: \(value)")
                    }
                    levels.append(level)
                default:
                    try setUnique(&values, key: key, value: value)
                }
                continue
            }
            guard path == nil else { throw CLIError("Only one input path is accepted") }
            path = argument
        }
        if values["--manifest"] != nil && path != nil {
            throw CLIError("Use either an input path or --manifest, not both")
        }
        if !validates, values["--max-score"] != nil { throw CLIError("--max-score is only valid for debt validate") }
        let format = try debtFormat(values["--format"], validates: validates)
        let jobs = try optionalInteger(values["--jobs"], named: "--jobs", range: 1...64)
        let preset = try optionalRaw(DebtAnalysisPreset.self, values["--preset"], named: "debt preset")
        let aggregation = try optionalRaw(DebtAggregationStrategy.self, values["--aggregation"], named: "debt aggregation")
        let minPriority = try optionalRaw(Priority.self, values["--min-priority"], named: "minimum priority")
        let minScore = try optionalScore(values["--min-score"], named: "--min-score")
        let top = try optionalInteger(values["--top"], named: "--top", range: 0...Int.max)
        let head = try optionalInteger(values["--head"], named: "--head", range: 0...Int.max)
        let tail = try optionalInteger(values["--tail"], named: "--tail", range: 0...Int.max)
        let hasDebtOverrides = preset != nil || aggregation != nil || minScore != nil || minPriority != nil
            || !categories.isEmpty || !levels.isEmpty || top != nil || head != nil || tail != nil
        let options = hasDebtOverrides
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
        let request = AnalysisRequest(
            path: path ?? ".",
            manifestPath: values["--manifest"],
            configurationPath: values["--config"],
            outputPath: values["--output"],
            stampPath: values["--stamp"],
            format: format,
            jobs: jobs,
            exclude: exclusions,
            debtAnalysisOptions: options,
            enableDebtAnalysis: true,
            lcovPath: values["--lcov"]
        )
        let maxScore = try optionalScore(values["--max-score"], named: "--max-score")
        if validates, maxScore == nil { throw CLIError("Missing required --max-score for debt validate") }
        let validation = maxScore.map { DebtValidationOptions(maxScore: $0, quiet: quiet) }
        return DebtParsedArguments(request: request, validation: validation)
    }

    private func debtFormat(_ value: String?, validates: Bool) throws -> ReportFormat {
        guard let value else { return validates ? .debtCompact : .debtText }
        switch value {
        case "json", "debt-json": return .debtJSON
        case "markdown", "md", "debt-markdown": return .debtMarkdown
        case "dot", "debt-dot": return .debtDot
        case "text", "plain", "debt-text": return .debtText
        case "compact", "debt-compact": return .debtCompact
        case "debtmap-json": return .debtmapJSON
        default: throw CLIError("Invalid debt format: \(value)")
        }
    }

    private func optionalRaw<T: RawRepresentable>(_ type: T.Type, _ value: String?, named name: String) throws -> T?
    where T.RawValue == String {
        guard let value else { return nil }
        guard let decoded = T(rawValue: value) else { throw CLIError("Invalid \(name): \(value)") }
        return decoded
    }

    private func optionalInteger(_ value: String?, named name: String, range: ClosedRange<Int>) throws -> Int? {
        guard let value else { return nil }
        guard let number = Int(value), range.contains(number) else {
            throw CLIError("Invalid integer for \(name): \(value)")
        }
        return number
    }

    private func optionalScore(_ value: String?, named name: String) throws -> Double? {
        guard let value else { return nil }
        guard let score = Double(value), (0...100).contains(score) else {
            throw CLIError("Invalid score for \(name): \(value)")
        }
        return score
    }

    private func setUnique(_ values: inout [String: String], key: String, value: String) throws {
        guard values[key] == nil else { throw CLIError("Duplicate option: \(key)") }
        values[key] = value
    }
}

private struct DebtParsedArguments {
    let request: AnalysisRequest
    let validation: DebtValidationOptions?
}
