public enum DebtReportComparisonSchema {
    public static let currentVersion = 1
}

public struct DebtReportComparison: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let beforeReportSchemaVersion: Int
    public let afterReportSchemaVersion: Int
    public let summary: DebtReportComparisonSummary
    public let itemChanges: DebtReportItemChanges
    public let aggregationChanges: DebtReportAggregationChanges
    public let missingEvidence: DebtStringSetDelta
}

public struct DebtReportComparisonSummary: Codable, Equatable, Sendable {
    public let beforeItemCount: Int
    public let afterItemCount: Int
    public let addedItemCount: Int
    public let removedItemCount: Int
    public let changedItemCount: Int
    public let unchangedItemCount: Int
    public let beforeTotalScore: Double
    public let afterTotalScore: Double
    public let totalScoreDelta: Double
    public let beforeUnavailableEvidenceCount: Int
    public let afterUnavailableEvidenceCount: Int
    public let unavailableEvidenceDelta: Int
    public let addedAggregationCount: Int
    public let removedAggregationCount: Int
    public let changedAggregationCount: Int
}

public struct DebtReportItemChanges: Codable, Equatable, Sendable {
    public let added: [DebtReportItemSnapshot]
    public let removed: [DebtReportItemSnapshot]
    public let changed: [DebtReportChangedItem]
    public let unchangedIDs: [String]
}

public struct DebtReportAggregationChanges: Codable, Equatable, Sendable {
    public let added: [DebtReportAggregationSnapshot]
    public let removed: [DebtReportAggregationSnapshot]
    public let changed: [DebtReportChangedAggregation]
    public let unchangedIDs: [String]
}

public struct DebtReportItemSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let level: DebtAggregationLevel
    public let location: DebtLocation
    public let score: Double?
    public let priority: Priority?
    public let evidenceIDs: [String]
    public let unavailableEvidenceIDs: [String]
}

public struct DebtReportChangedItem: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let moved: Bool
    public let beforeLocation: DebtLocation
    public let afterLocation: DebtLocation
    public let score: DebtDoubleDelta
    public let priority: DebtPriorityDelta
    public let evidence: DebtStringSetDelta
    public let unavailableEvidence: DebtStringSetDelta
}

public struct DebtReportAggregationSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let level: DebtAggregationLevel
    public let location: DebtLocation
    public let memberItemIDs: [String]
    public let score: Double?
    public let priority: Priority?
}

public struct DebtReportChangedAggregation: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let level: DebtAggregationLevel
    public let moved: Bool
    public let beforeLocation: DebtLocation
    public let afterLocation: DebtLocation
    public let score: DebtDoubleDelta
    public let priority: DebtPriorityDelta
    public let memberItemIDs: DebtStringSetDelta
}

public struct DebtDoubleDelta: Codable, Equatable, Sendable {
    public let before: Double?
    public let after: Double?
    public let delta: Double?
}

public struct DebtPriorityDelta: Codable, Equatable, Sendable {
    public let before: Priority?
    public let after: Priority?
}

public struct DebtStringSetDelta: Codable, Equatable, Sendable {
    public let added: [String]
    public let removed: [String]
}

public struct DebtImprovementValidation: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let threshold: Double
    public let observedImprovement: Double
    public let passed: Bool
    public let exitStatus: Int32
    public let comparisonSummary: DebtReportComparisonSummary

    public init(
        schemaVersion: Int = DebtReportComparisonSchema.currentVersion,
        threshold: Double,
        observedImprovement: Double,
        passed: Bool,
        exitStatus: Int32,
        comparisonSummary: DebtReportComparisonSummary
    ) {
        self.schemaVersion = schemaVersion
        self.threshold = threshold
        self.observedImprovement = observedImprovement
        self.passed = passed
        self.exitStatus = exitStatus
        self.comparisonSummary = comparisonSummary
    }
}

