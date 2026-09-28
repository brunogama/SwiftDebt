import Foundation
import SwiftDebtCore

package enum DebtReferenceTimeParser {
    package static let example = "2026-09-12T00:00:00Z"

    package static func parse(_ value: String) -> Date? {
        let formats: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
        ]
        for format in formats {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

struct WorkspaceConfiguration: Decodable {
    var typeScope: TypeScope = .classes
    var scoring: ScoringMode = .none
    var format: ReportFormat = .text
    var thresholds: [String: Int] = [:]
    var exclude: [String] = []
    var jobs = Self.defaultJobs
    var failOnViolation = false
    var strictSyntax = false
    var minimumDuplicateLines = 11
    var maximumDuplicateComparisons = 250_000
    var maximumFileBytes = 16 * 1024 * 1024
    var debtAnalysis: DebtAnalysisOptions?
    var debtValidation: WorkspaceDebtValidation?
    var lcovPath: String?
    var debtReferenceTime: Date?

    /// Parsing is embarrassingly parallel; bounded to keep memory predictable.
    static var defaultJobs: Int { min(8, max(1, ProcessInfo.processInfo.activeProcessorCount)) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case typeScope, scoring, format, thresholds, exclude, jobs, failOnViolation, strictSyntax
        case minimumDuplicateLines, maximumDuplicateComparisons, maximumFileBytes, debtAnalysis,
            debtValidation,
            lcovPath
        case debtReferenceTime
    }
    init() {}
    init(from decoder: any Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw AnalysisFailure.invalidConfiguration(
                "Unknown configuration keys: \(unknown.joined(separator: ", "))")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        typeScope = try values.decodeIfPresent(TypeScope.self, forKey: .typeScope) ?? typeScope
        scoring = try values.decodeIfPresent(ScoringMode.self, forKey: .scoring) ?? scoring
        format = try values.decodeIfPresent(ReportFormat.self, forKey: .format) ?? format
        thresholds =
            try values.decodeIfPresent([String: Int].self, forKey: .thresholds) ?? thresholds
        exclude = try values.decodeIfPresent([String].self, forKey: .exclude) ?? exclude
        jobs = try values.decodeIfPresent(Int.self, forKey: .jobs) ?? jobs
        failOnViolation =
            try values.decodeIfPresent(Bool.self, forKey: .failOnViolation) ?? failOnViolation
        strictSyntax = try values.decodeIfPresent(Bool.self, forKey: .strictSyntax) ?? strictSyntax
        minimumDuplicateLines =
            try values.decodeIfPresent(Int.self, forKey: .minimumDuplicateLines)
            ?? minimumDuplicateLines
        maximumDuplicateComparisons =
            try values.decodeIfPresent(Int.self, forKey: .maximumDuplicateComparisons)
            ?? maximumDuplicateComparisons
        maximumFileBytes =
            try values.decodeIfPresent(Int.self, forKey: .maximumFileBytes) ?? maximumFileBytes
        debtAnalysis = try values.decodeIfPresent(DebtAnalysisOptions.self, forKey: .debtAnalysis)
        debtValidation = try values.decodeIfPresent(
            WorkspaceDebtValidation.self, forKey: .debtValidation)
        lcovPath = try values.decodeIfPresent(String.self, forKey: .lcovPath)
        if let value = try values.decodeIfPresent(String.self, forKey: .debtReferenceTime) {
            guard let date = DebtReferenceTimeParser.parse(value) else {
                throw AnalysisFailure.invalidConfiguration(
                    "debtReferenceTime must be an ISO-8601 timestamp such as \(DebtReferenceTimeParser.example)"
                )
            }
            debtReferenceTime = date
        }
    }

    func analysisOptions(overrides: AnalysisRequest) throws -> AnalysisOptions {
        var limits: [Metric: Int] = [:]
        for (key, value) in thresholds {
            guard let metric = Metric(rawValue: key) else {
                throw AnalysisFailure.invalidConfiguration("Unknown metric in thresholds: \(key)")
            }
            limits[metric] = value
        }
        limits.merge(overrides.thresholds) { _, new in new }
        let options = AnalysisOptions(
            typeScope: overrides.typeScope ?? typeScope, scoring: overrides.scoring ?? scoring,
            thresholds: limits, minimumDuplicateLines: minimumDuplicateLines,
            maximumDuplicateComparisons: maximumDuplicateComparisons,
            strictSyntax: overrides.strictSyntax || strictSyntax
        )
        try options.validate()
        guard (1...64).contains(overrides.jobs ?? jobs),
            (overrides.maximumFileBytes ?? maximumFileBytes) > 0
        else {
            throw AnalysisFailure.invalidConfiguration(
                "jobs must be 1...64 and maximumFileBytes must be positive")
        }
        if let lcovPath {
            try validateRelativePath(lcovPath, description: "LCOV path")
        }
        if let lcovPath = overrides.lcovPath, !(lcovPath as NSString).isAbsolutePath {
            try validateRelativePath(lcovPath, description: "LCOV path")
        }
        for path in exclude + overrides.exclude {
            guard !path.isEmpty, !(path as NSString).isAbsolutePath,
                !path.split(separator: "/").contains(".."),
                !path.contains("*"), !path.contains("?")
            else {
                throw AnalysisFailure.invalidConfiguration(
                    "Excludes must be nonempty relative path prefixes, not globs: \(path)")
            }
        }
        return options
    }

    private func validateRelativePath(_ path: String, description: String) throws {
        guard !path.isEmpty, !path.split(separator: "/").contains(".."), !path.contains("*"),
            !path.contains("?")
        else {
            throw AnalysisFailure.invalidConfiguration(
                "\(description) must be a nonempty path, not a glob: \(path)")
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

struct WorkspaceDebtValidation: Decodable, Sendable {
    let maxScore: Double

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case maxScore
    }

    init(from decoder: any Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw AnalysisFailure.invalidConfiguration(
                "Unknown debt validation configuration keys: \(unknown.joined(separator: ", "))")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        maxScore = try values.decode(Double.self, forKey: .maxScore)
        guard (0...100).contains(maxScore) else {
            throw AnalysisFailure.invalidConfiguration(
                "debtValidation.maxScore must be between 0 and 100")
        }
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
