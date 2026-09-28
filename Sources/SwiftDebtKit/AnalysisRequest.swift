import Foundation
import SwiftDebtCore

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
    public let debtAnalysisOptions: DebtAnalysisOptions?
    public let enableDebtAnalysis: Bool
    public let lcovPath: String?
    public let debtReferenceTime: Date?
    /// Absolute path to Git for history evidence; nil searches PATH.
    public let gitExecutablePath: String?
    public let profileOutputPath: String?
    public let pluginEvidenceLimitations: Bool
    public let maximumFileBytes: Int?

    public init(
        path: String = ".", manifestPath: String? = nil, configurationPath: String? = nil,
        outputPath: String? = nil, stampPath: String? = nil, typeScope: TypeScope? = nil,
        scoring: ScoringMode? = nil, format: ReportFormat? = nil, jobs: Int? = nil,
        failOnViolation: Bool = false, strictSyntax: Bool = false, exclude: [String] = [],
        thresholds: [Metric: Int] = [:], debtAnalysisOptions: DebtAnalysisOptions? = nil,
        enableDebtAnalysis: Bool = false, lcovPath: String? = nil, debtReferenceTime: Date? = nil,
        gitExecutablePath: String? = nil,
        profileOutputPath: String? = nil,
        pluginEvidenceLimitations: Bool = false,
        maximumFileBytes: Int? = nil
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
        self.debtAnalysisOptions = debtAnalysisOptions
        self.enableDebtAnalysis = enableDebtAnalysis
        self.lcovPath = lcovPath
        self.debtReferenceTime = debtReferenceTime
        self.gitExecutablePath = gitExecutablePath
        self.profileOutputPath = profileOutputPath
        self.pluginEvidenceLimitations = pluginEvidenceLimitations
        self.maximumFileBytes = maximumFileBytes
    }
}

public struct AnalysisRunResult: Sendable {
    public let report: AnalysisReport
    /// Empty when output was written to a file.
    public let standardOutput: String
    /// 0 = success, 1 = opted-in threshold gate, 2 = incomplete analysis.
    public let exitStatus: Int32
    public let rankedDebtAnalysis: RankedDebtAnalysis?
    public let profile: AnalysisProfile?

    public init(
        report: AnalysisReport,
        standardOutput: String,
        exitStatus: Int32,
        rankedDebtAnalysis: RankedDebtAnalysis? = nil,
        profile: AnalysisProfile? = nil
    ) {
        self.report = report
        self.standardOutput = standardOutput
        self.exitStatus = exitStatus
        self.rankedDebtAnalysis = rankedDebtAnalysis
        self.profile = profile
    }
}
