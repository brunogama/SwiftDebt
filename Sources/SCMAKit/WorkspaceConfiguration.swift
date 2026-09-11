import Foundation
import SCMACore

struct WorkspaceConfiguration: Decodable {
    var typeScope: TypeScope = .classes
    var scoring: ScoringMode = .none
    var format: ReportFormat = .text
    var thresholds: [String: Int] = [:]
    var exclude: [String] = []
    var jobs = WorkspaceConfiguration.defaultJobs
    var failOnViolation = false
    var strictSyntax = false
    var minimumDuplicateLines = 11
    var maximumDuplicateComparisons = 250_000
    var maximumFileBytes = 16 * 1024 * 1024

    /// Parsing is embarrassingly parallel; bounded to keep memory predictable.
    static var defaultJobs: Int { min(8, max(1, ProcessInfo.processInfo.activeProcessorCount)) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case typeScope, scoring, format, thresholds, exclude, jobs, failOnViolation, strictSyntax
        case minimumDuplicateLines, maximumDuplicateComparisons, maximumFileBytes
    }
    init() {}
    init(from decoder: any Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw AnalysisFailure.invalidConfiguration("Unknown configuration keys: \(unknown.joined(separator: ", "))")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        typeScope = try values.decodeIfPresent(TypeScope.self, forKey: .typeScope) ?? typeScope
        scoring = try values.decodeIfPresent(ScoringMode.self, forKey: .scoring) ?? scoring
        format = try values.decodeIfPresent(ReportFormat.self, forKey: .format) ?? format
        thresholds = try values.decodeIfPresent([String: Int].self, forKey: .thresholds) ?? thresholds
        exclude = try values.decodeIfPresent([String].self, forKey: .exclude) ?? exclude
        jobs = try values.decodeIfPresent(Int.self, forKey: .jobs) ?? jobs
        failOnViolation = try values.decodeIfPresent(Bool.self, forKey: .failOnViolation) ?? failOnViolation
        strictSyntax = try values.decodeIfPresent(Bool.self, forKey: .strictSyntax) ?? strictSyntax
        minimumDuplicateLines =
            try values.decodeIfPresent(Int.self, forKey: .minimumDuplicateLines) ?? minimumDuplicateLines
        maximumDuplicateComparisons =
            try values.decodeIfPresent(Int.self, forKey: .maximumDuplicateComparisons) ?? maximumDuplicateComparisons
        maximumFileBytes = try values.decodeIfPresent(Int.self, forKey: .maximumFileBytes) ?? maximumFileBytes
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
        guard (1...64).contains(overrides.jobs ?? jobs), maximumFileBytes > 0 else {
            throw AnalysisFailure.invalidConfiguration("jobs must be 1...64 and maximumFileBytes must be positive")
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

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

public struct AnalysisRequest: Sendable {
    public let path: String
    public let manifestPath: String?
    public let configurationPath: String?
    public let outputPath: String?
    public let stampPath: String?
    public let typeScope: TypeScope?
    public let scoring: ScoringMode?
    public let format: ReportFormat?
    public let jobs: Int?
    public let failOnViolation: Bool
    public let strictSyntax: Bool
    public let exclude: [String]
    public let thresholds: [Metric: Int]

    public init(
        path: String = ".", manifestPath: String? = nil, configurationPath: String? = nil,
        outputPath: String? = nil, stampPath: String? = nil, typeScope: TypeScope? = nil,
        scoring: ScoringMode? = nil, format: ReportFormat? = nil, jobs: Int? = nil,
        failOnViolation: Bool = false, strictSyntax: Bool = false, exclude: [String] = [],
        thresholds: [Metric: Int] = [:]
    ) {
        self.path = path
        self.manifestPath = manifestPath
        self.configurationPath = configurationPath
        self.outputPath = outputPath
        self.stampPath = stampPath
        self.typeScope = typeScope
        self.scoring = scoring
        self.format = format
        self.jobs = jobs
        self.failOnViolation = failOnViolation
        self.strictSyntax = strictSyntax
        self.exclude = exclude
        self.thresholds = thresholds
    }
}

public struct AnalysisRunResult: Sendable {
    public let report: AnalysisReport
    /// Empty when output was written to a file.
    public let standardOutput: String
    /// 0 = success, 1 = opted-in threshold gate, 2 = incomplete analysis.
    public let exitStatus: Int32
}
