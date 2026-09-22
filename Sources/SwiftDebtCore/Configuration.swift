/// The ten metric identifiers used in the SCMA paper, in paper order.
public enum Metric: String, Codable, CaseIterable, Sendable {
    case locc = "LOCC"
    case wmcc = "WMCC"
    case nomc = "NOMC"
    case nogc = "NOGC"
    case nocc = "NOCC"
    case noav = "NOAV"
    case locf = "LOCF"
    case ccf = "CCF"
    case nopf = "NOPF"
    case dc = "DC"

    public var title: String {
        switch self {
        case .locc: "Line of Code by Classes"
        case .wmcc: "Weighed Method Count by Classes"
        case .nomc: "Number of Methods by Classes"
        case .nogc: "Number of Global Variables by Classes"
        case .nocc: "Number of Couplings by Classes"
        case .noav: "Number of Accessed Methods by Variables"
        case .locf: "Line of Code by Functions"
        case .ccf: "Cyclomatic Complexity by Functions"
        case .nopf: "Number of parameters by Functions"
        case .dc: "Duplicate Code"
        }
    }

    /// The paper does not provide violation thresholds for the other five metrics.
    public var paperThreshold: Int? {
        switch self {
        case .locc: 500
        case .wmcc: 200
        case .ccf: 20
        case .nopf, .dc: 10
        default: nil
        }
    }
}

public enum TypeScope: String, Codable, Sendable {
    case classes
    /// An explicitly non-paper extension to structs, enums and actors.
    case nominals
}

public enum ScoringMode: String, Codable, Sendable {
    case none
    /// Literal equations in Table I. Scores are NOT constrained to 0...5.
    case paper
    /// Literal equations followed by an explicit clamp to 0...5. Not a repaired model.
    case bounded
    /// `bounded` plus one documented repair: the DC ratio is `duplicatedLines / totalLines`
    /// instead of the printed `duplicatedLines * totalLines / totalParams`.
    case corrected
}

/// Immutable analysis policy. Core has no Foundation, I/O, parser, or platform dependency.
public struct AnalysisOptions: Sendable {
    public let typeScope: TypeScope
    public let scoring: ScoringMode
    public let thresholds: [Metric: Int]
    public let minimumDuplicateLines: Int
    public let maximumDuplicateComparisons: Int
    /// When false (default), a file with parse errors is skipped with a warning and the
    /// report stays complete. When true, any parse error makes the analysis incomplete.
    public let strictSyntax: Bool

    public init(
        typeScope: TypeScope = .classes,
        scoring: ScoringMode = .none,
        thresholds: [Metric: Int] = [:],
        minimumDuplicateLines: Int = 11,
        maximumDuplicateComparisons: Int = 250_000,
        strictSyntax: Bool = false
    ) {
        self.typeScope = typeScope
        self.scoring = scoring
        self.thresholds = thresholds
        self.minimumDuplicateLines = minimumDuplicateLines
        self.maximumDuplicateComparisons = maximumDuplicateComparisons
        self.strictSyntax = strictSyntax
    }

    public func threshold(for metric: Metric) -> Int? {
        thresholds[metric] ?? metric.paperThreshold
    }

    public func validate() throws {
        guard minimumDuplicateLines >= 2 else {
            throw AnalysisFailure.invalidConfiguration("minimumDuplicateLines must be at least 2")
        }
        if let limit = threshold(for: .dc), minimumDuplicateLines - 1 > limit {
            throw AnalysisFailure.invalidConfiguration(
                "minimumDuplicateLines must not exceed the DC threshold plus one; otherwise shorter violations would be hidden"
            )
        }
        if scoring != .none && minimumDuplicateLines != 11 {
            throw AnalysisFailure.invalidConfiguration(
                "paper/bounded scoring requires minimumDuplicateLines = 11; use scoring = none for a custom clone floor"
            )
        }
        guard maximumDuplicateComparisons > 0 else {
            throw AnalysisFailure.invalidConfiguration("maximumDuplicateComparisons must be positive")
        }
        guard thresholds.values.allSatisfy({ $0 >= 0 }) else {
            throw AnalysisFailure.invalidConfiguration("thresholds must be nonnegative")
        }
    }
}

public enum AnalysisFailure: Error, Sendable, CustomStringConvertible {
    case invalidConfiguration(String)
    case duplicateBudgetExceeded(Int)
    case noSources

    public var description: String {
        switch self {
        case .invalidConfiguration(let message): message
        case .duplicateBudgetExceeded(let limit):
            "Duplicate comparison budget (\(limit)) exceeded; no complete report was produced. "
                + "Raise maximumDuplicateComparisons or narrow the analysis scope."
        case .noSources: "No Swift source files were selected."
        }
    }
}

public enum ReportFormat: String, Codable, CaseIterable, Sendable {
    case text, json, csv, html, diagnostics
    case debtJSON = "debt-json"
    case debtMarkdown = "debt-markdown"
    case debtDot = "debt-dot"
    case debtText = "debt-text"
    case debtCompact = "debt-compact"
    case debtmapJSON = "debtmap-json"
    case debtDashboard = "debt-dashboard"

    public var isDebtReportFormat: Bool {
        switch self {
        case .text, .json, .csv, .html, .diagnostics:
            false
        case .debtJSON, .debtMarkdown, .debtDot, .debtText, .debtCompact, .debtmapJSON, .debtDashboard:
            true
        }
    }
}
