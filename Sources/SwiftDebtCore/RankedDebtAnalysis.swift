public enum DebtAnalysisPreset: String, Codable, CaseIterable, Sendable {
    case strict
    case balanced
    case lenient
}

public enum DebtAggregationStrategy: String, Codable, CaseIterable, Sendable {
    case none
    case file
    case aggregateOnly
}

public struct DebtAnalysisOptions: Codable, Equatable, Sendable {
    public let preset: DebtAnalysisPreset
    public let aggregationStrategy: DebtAggregationStrategy
    public let minScore: Double?
    public let minPriority: Priority?
    public let categories: [String]
    public let levels: [DebtAggregationLevel]
    public let top: Int?
    public let head: Int?
    public let tail: Int?
    public let problematicItemScoreThreshold: Double
    public let scoringPolicy: DebtScoringPolicy

    public init(
        preset: DebtAnalysisPreset = .balanced,
        aggregationStrategy: DebtAggregationStrategy = .file,
        minScore: Double? = nil,
        minPriority: Priority? = nil,
        categories: [String] = [],
        levels: [DebtAggregationLevel] = [],
        top: Int? = nil,
        head: Int? = nil,
        tail: Int? = nil,
        problematicItemScoreThreshold: Double? = nil,
        scoringPolicy: DebtScoringPolicy? = nil
    ) {
        self.preset = preset
        self.aggregationStrategy = aggregationStrategy
        self.minScore = minScore
        self.minPriority = minPriority
        self.categories = categories.sorted()
        self.levels = levels.sorted { $0.rawValue < $1.rawValue }
        self.top = top
        self.head = head
        self.tail = tail
        self.problematicItemScoreThreshold = problematicItemScoreThreshold ?? Self.defaultProblematicThreshold(for: preset)
        self.scoringPolicy = scoringPolicy ?? Self.defaultScoringPolicy(for: preset)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case preset
        case aggregationStrategy
        case minScore
        case minPriority
        case categories
        case levels
        case top
        case head
        case tail
        case problematicItemScoreThreshold
        case scoringPolicy
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        let unknown = raw.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw AnalysisFailure.invalidConfiguration("Unknown debt analysis configuration keys: \(unknown.joined(separator: ", "))")
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try values.decodeIfPresent(DebtAnalysisPreset.self, forKey: .preset) ?? .balanced
        self.init(
            preset: preset,
            aggregationStrategy: try values.decodeIfPresent(DebtAggregationStrategy.self, forKey: .aggregationStrategy) ?? .file,
            minScore: try values.decodeIfPresent(Double.self, forKey: .minScore),
            minPriority: try values.decodeIfPresent(Priority.self, forKey: .minPriority),
            categories: try values.decodeIfPresent([String].self, forKey: .categories) ?? [],
            levels: try values.decodeIfPresent([DebtAggregationLevel].self, forKey: .levels) ?? [],
            top: try values.decodeIfPresent(Int.self, forKey: .top),
            head: try values.decodeIfPresent(Int.self, forKey: .head),
            tail: try values.decodeIfPresent(Int.self, forKey: .tail),
            problematicItemScoreThreshold: try values.decodeIfPresent(Double.self, forKey: .problematicItemScoreThreshold),
            scoringPolicy: try values.decodeIfPresent(DebtScoringPolicy.self, forKey: .scoringPolicy)
        )
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    private static func defaultProblematicThreshold(for preset: DebtAnalysisPreset) -> Double {
        switch preset {
        case .strict: 40
        case .balanced: 70
        case .lenient: 85
        }
    }

    private static func defaultScoringPolicy(for preset: DebtAnalysisPreset) -> DebtScoringPolicy {
        switch preset {
        case .strict:
            DebtScoringPolicy(priorityThresholds: PriorityThresholds(medium: 25, high: 50, critical: 75))
        case .balanced:
            DebtScoringPolicy(priorityThresholds: PriorityThresholds())
        case .lenient:
            DebtScoringPolicy(priorityThresholds: PriorityThresholds(medium: 55, high: 80, critical: 92))
        }
    }
}

public struct CompactDebtItem: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let level: DebtAggregationLevel
    public let score: Double?
    public let priority: Priority?
    public let location: DebtLocation

    public init(
        id: String,
        displayName: String,
        level: DebtAggregationLevel,
        score: Double?,
        priority: Priority?,
        location: DebtLocation
    ) {
        self.id = id
        self.displayName = displayName
        self.level = level
        self.score = score
        self.priority = priority
        self.location = location
    }
}

public struct RankedDebtItem: Codable, Equatable, Sendable {
    public let item: DebtItem
    public let score: DebtScore
    public let category: String
    public let explanation: String
    public let recommendation: String

    public init(
        item: DebtItem,
        score: DebtScore,
        category: String,
        explanation: String,
        recommendation: String
    ) {
        self.item = item
        self.score = score
        self.category = category
        self.explanation = explanation
        self.recommendation = recommendation
    }
}

public struct DebtAnalysisSummary: Codable, Equatable, Sendable {
    public let totalItemCount: Int
    public let rankedItemCount: Int
    public let aggregationCount: Int
    public let unavailableEvidenceCount: Int
    public let priorityCounts: [String: Int]

    public init(
        totalItemCount: Int,
        rankedItemCount: Int,
        aggregationCount: Int,
        unavailableEvidenceCount: Int,
        priorityCounts: [String: Int]
    ) {
        self.totalItemCount = totalItemCount
        self.rankedItemCount = rankedItemCount
        self.aggregationCount = aggregationCount
        self.unavailableEvidenceCount = unavailableEvidenceCount
        self.priorityCounts = priorityCounts
    }
}

public struct RankedDebtAnalysis: Codable, Equatable, Sendable {
    public let options: DebtAnalysisOptions
    public let items: [RankedDebtItem]
    public let aggregations: [DebtAggregation]
    public let compactItems: [CompactDebtItem]
    public let summary: DebtAnalysisSummary

    public init(
        options: DebtAnalysisOptions,
        items: [RankedDebtItem],
        aggregations: [DebtAggregation],
        compactItems: [CompactDebtItem],
        summary: DebtAnalysisSummary
    ) {
        self.options = options
        self.items = items
        self.aggregations = aggregations
        self.compactItems = compactItems
        self.summary = summary
    }
}
