/// Groups a `RuleDefinition` catalog along the four axes PRD FR-18 names -
/// Support State, `RuleCategory`, `RuleScope`, and `DetectionMode` - so a
/// caller can answer "how many rules are Supported vs Partial vs ... broken
/// down by category/scope/mode" against typed keys, never by parsing
/// strings out of a rendered report.
///
/// This is read-only, derived state: it holds no catalog of its own and
/// never mutates the `RuleDefinition`s it is built from (Invariant Q2 -
/// coverage reporting is independent of any `RuleImplementation`).
public struct CoverageReport: Sendable {
    /// The full input catalog, unmodified.
    public let rules: [RuleDefinition]

    public let bySupportState: [SupportState: [RuleDefinition]]
    public let byCategory: [RuleCategory: [RuleDefinition]]
    public let byScope: [RuleScope: [RuleDefinition]]
    public let byDetectionMode: [DetectionMode: [RuleDefinition]]

    public init(rules: [RuleDefinition]) {
        self.rules = rules
        self.bySupportState = Dictionary(grouping: rules) { $0.metadata.supportState }
        self.byCategory = Dictionary(grouping: rules) { $0.metadata.category }
        self.byScope = Dictionary(grouping: rules) { $0.scope }
        self.byDetectionMode = Dictionary(grouping: rules) { $0.mode }
    }

    /// Total rule count in the catalog this report was built from.
    public var totalRuleCount: Int { rules.count }

    public func count(for supportState: SupportState) -> Int {
        bySupportState[supportState]?.count ?? 0
    }

    public func count(for category: RuleCategory) -> Int {
        byCategory[category]?.count ?? 0
    }

    public func count(for scope: RuleScope) -> Int {
        byScope[scope]?.count ?? 0
    }

    public func count(for mode: DetectionMode) -> Int {
        byDetectionMode[mode]?.count ?? 0
    }

    /// Support-state counts for every case, including zero counts for
    /// states no rule in the catalog currently occupies - so a caller can
    /// render a complete breakdown without special-casing absent keys.
    public var supportStateCounts: [SupportState: Int] {
        Dictionary(uniqueKeysWithValues: SupportState.allCases.map { ($0, count(for: $0)) })
    }

    public var categoryCounts: [RuleCategory: Int] {
        Dictionary(uniqueKeysWithValues: RuleCategory.allCases.map { ($0, count(for: $0)) })
    }

    public var scopeCounts: [RuleScope: Int] {
        Dictionary(uniqueKeysWithValues: RuleScope.allCases.map { ($0, count(for: $0)) })
    }

    public var detectionModeCounts: [DetectionMode: Int] {
        Dictionary(uniqueKeysWithValues: DetectionMode.allCases.map { ($0, count(for: $0)) })
    }
}

extension Array where Element == RuleDefinition {
    /// Looks up a single `RuleDefinition` by its `RuleIdentity` (PRD FR-19 -
    /// rule inspection). `RuleDefinition` already carries provenance
    /// (`metadata.provenance`), requirements, evidence contract, and semantic
    /// revision, so no separate inspection wrapper type is introduced here:
    /// the full record this accessor returns already answers FR-19.
    public func ruleDefinition(for identity: RuleIdentity) -> RuleDefinition? {
        first { $0.identity == identity }
    }
}
