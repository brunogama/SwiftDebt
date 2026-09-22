public enum DebtReportSchema {
    public static let currentVersion = 1
}

public struct DebtReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let generator: String
    public let options: DebtAnalysisOptions
    public let summary: DebtAnalysisSummary
    public let items: [DebtReportItem]
    public let aggregations: [DebtReportAggregation]
    public let compactItems: [CompactDebtItem]
    public let missingEvidence: [DebtReportMissingEvidence]
    public let dependencyGraph: DebtReportDependencyGraph?

    public init(
        schemaVersion: Int = DebtReportSchema.currentVersion,
        reportKind: String = "swiftscma-debt-report",
        generator: String = "SwiftSCMA",
        options: DebtAnalysisOptions,
        summary: DebtAnalysisSummary,
        items: [DebtReportItem],
        aggregations: [DebtReportAggregation],
        compactItems: [CompactDebtItem],
        missingEvidence: [DebtReportMissingEvidence],
        dependencyGraph: DebtReportDependencyGraph? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.reportKind = reportKind
        self.generator = generator
        self.options = options
        self.summary = summary
        self.items = items
        self.aggregations = aggregations
        self.compactItems = compactItems
        self.missingEvidence = missingEvidence
        self.dependencyGraph = dependencyGraph
    }
}

/// The deterministic dependency and call graph facts carried by a debt report.
///
/// This is a presentation projection of `SwiftDependencyGraph`. Coupling and
/// scoring evidence remain in the report items, while nodes, edges, and graph
/// statistics let report consumers visualize the graph without rerunning
/// analysis or parsing DOT.
public struct DebtReportDependencyGraph: Codable, Equatable, Sendable {
    public let nodes: [SwiftGraphNode]
    public let edges: [SwiftGraphEdge]
    public let statistics: CallGraphStatistics

    public init(
        nodes: [SwiftGraphNode],
        edges: [SwiftGraphEdge],
        statistics: CallGraphStatistics
    ) {
        self.nodes = nodes
        self.edges = edges
        self.statistics = statistics
    }
}

public struct DebtReportItem: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let level: DebtAggregationLevel
    public let location: DebtLocation
    public let category: String
    public let score: Double?
    public let priority: Priority?
    public let explanation: String
    public let recommendation: String
    public let evidence: [DebtEvidence]
    public let scoreBreakdown: DebtScoreBreakdown

    public init(
        id: String,
        displayName: String,
        level: DebtAggregationLevel,
        location: DebtLocation,
        category: String,
        score: Double?,
        priority: Priority?,
        explanation: String,
        recommendation: String,
        evidence: [DebtEvidence],
        scoreBreakdown: DebtScoreBreakdown
    ) {
        self.id = id
        self.displayName = displayName
        self.level = level
        self.location = location
        self.category = category
        self.score = score
        self.priority = priority
        self.explanation = explanation
        self.recommendation = recommendation
        self.evidence = evidence
        self.scoreBreakdown = scoreBreakdown
    }
}

public struct DebtReportAggregation: Codable, Equatable, Sendable {
    public let id: String
    public let level: DebtAggregationLevel
    public let displayName: String
    public let location: DebtLocation
    public let memberItemIDs: [String]
    public let score: Double?
    public let priority: Priority?

    public init(
        id: String,
        level: DebtAggregationLevel,
        displayName: String,
        location: DebtLocation,
        memberItemIDs: [String],
        score: Double?,
        priority: Priority?
    ) {
        self.id = id
        self.level = level
        self.displayName = displayName
        self.location = location
        self.memberItemIDs = memberItemIDs
        self.score = score
        self.priority = priority
    }
}

public struct DebtReportMissingEvidence: Codable, Equatable, Sendable {
    public let itemID: String
    public let evidenceID: String
    public let kind: String
    public let requirement: DebtEvidenceRequirement
    public let configuredWeight: Double
    public let reason: String

    public init(
        itemID: String,
        evidenceID: String,
        kind: String,
        requirement: DebtEvidenceRequirement,
        configuredWeight: Double,
        reason: String
    ) {
        self.itemID = itemID
        self.evidenceID = evidenceID
        self.kind = kind
        self.requirement = requirement
        self.configuredWeight = configuredWeight
        self.reason = reason
    }
}

/// A deterministic projection for Debtmap-oriented automation.
///
/// This type is not the native SwiftSCMA debt-report model. It preserves the
/// ranked item identity, scores, actions and missing-evidence facts needed by
/// automation that expects Debtmap-like data while keeping the native schema in
/// `DebtReport`.
public struct DebtmapCompatibilityProjection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let projection: String
    public let projectionNote: String
    public let items: [DebtmapCompatibilityItem]
    public let missingEvidence: [DebtReportMissingEvidence]

    public init(
        schemaVersion: Int = 1,
        projection: String = "debtmap-compatibility",
        projectionNote: String =
            "Deterministic SwiftSCMA projection for Debtmap-oriented automation; not the native SwiftSCMA debt model.",
        items: [DebtmapCompatibilityItem],
        missingEvidence: [DebtReportMissingEvidence]
    ) {
        self.schemaVersion = schemaVersion
        self.projection = projection
        self.projectionNote = projectionNote
        self.items = items
        self.missingEvidence = missingEvidence
    }
}

public struct DebtmapCompatibilityItem: Codable, Equatable, Sendable {
    public let id: String
    public let entity: String
    public let level: DebtAggregationLevel
    public let location: DebtLocation
    public let priority: Priority?
    public let score: Double?
    public let evidenceKinds: [String]
    public let action: String

    public init(
        id: String,
        entity: String,
        level: DebtAggregationLevel,
        location: DebtLocation,
        priority: Priority?,
        score: Double?,
        evidenceKinds: [String],
        action: String
    ) {
        self.id = id
        self.entity = entity
        self.level = level
        self.location = location
        self.priority = priority
        self.score = score
        self.evidenceKinds = evidenceKinds
        self.action = action
    }
}
