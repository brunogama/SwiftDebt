public struct DebtAnalysisBuilder: Sendable {
    public let options: DebtAnalysisOptions

    public init(options: DebtAnalysisOptions = DebtAnalysisOptions()) {
        self.options = options
    }

    public func analyze(items: [DebtItem]) -> RankedDebtAnalysis {
        let scoring = DebtScoring(policy: options.scoringPolicy)
        let scored = items.map { item in
            RankedDebtItem(
                item: item,
                score: scoring.score(item),
                category: category(for: item),
                explanation: explanation(for: item),
                recommendation: recommendation(for: item)
            )
        }
        let filtered = limit(scored.filter(passesFilters).sorted(by: rankedOrder))
        let aggregations = makeAggregations(from: scored, scoring: scoring)
        let outputItems = options.aggregationStrategy == .aggregateOnly ? [] : filtered
        let compact = outputItems.map { ranked in
            CompactDebtItem(
                id: ranked.item.id,
                displayName: ranked.item.entity.displayName,
                level: ranked.item.entity.level,
                score: ranked.score.value,
                priority: ranked.score.priority,
                location: ranked.item.entity.location
            )
        }
        let unavailable = outputItems.reduce(0) { partial, ranked in
            partial + ranked.score.breakdown.unavailableEvidence.count
        }
        var priorityCounts: [String: Int] = [:]
        for ranked in outputItems {
            let key = ranked.score.priority?.rawValue ?? "unscored"
            priorityCounts[key, default: 0] += 1
        }
        return RankedDebtAnalysis(
            options: options,
            items: outputItems,
            aggregations: aggregations,
            compactItems: compact,
            summary: DebtAnalysisSummary(
                totalItemCount: items.count,
                rankedItemCount: outputItems.count,
                aggregationCount: aggregations.count,
                unavailableEvidenceCount: unavailable,
                priorityCounts: priorityCounts
            )
        )
    }

    private func passesFilters(_ ranked: RankedDebtItem) -> Bool {
        if !options.levels.isEmpty, !options.levels.contains(ranked.item.entity.level) { return false }
        if !options.categories.isEmpty {
            let matches = ranked.item.evidence.contains { evidence in
                options.categories.contains { category in
                    evidence.kind == category || evidence.kind.hasPrefix(category + ".")
                }
            }
            if !matches { return false }
        }
        if let minScore = options.minScore {
            guard let score = ranked.score.value, score >= minScore else { return false }
        }
        if let minPriority = options.minPriority {
            guard let priority = ranked.score.priority, priorityRank(priority) >= priorityRank(minPriority) else {
                return false
            }
        }
        return true
    }

    private func limit(_ ranked: [RankedDebtItem]) -> [RankedDebtItem] {
        if let tail = options.tail, tail >= 0 {
            return Array(ranked.suffix(tail))
        }
        let requested = [options.top, options.head].compactMap { $0 }.filter { $0 >= 0 }.min()
        guard let count = requested else { return ranked }
        return Array(ranked.prefix(count))
    }

    private func makeAggregations(from scored: [RankedDebtItem], scoring: DebtScoring) -> [DebtAggregation] {
        guard options.aggregationStrategy != .none else { return [] }
        let problematic = scored.filter { ranked in
            guard let value = ranked.score.value else { return false }
            return value >= options.problematicItemScoreThreshold
        }
        let grouped = Dictionary(grouping: problematic, by: { $0.item.entity.location.file ?? "" })
        return grouped.keys.sorted().compactMap { file in
            guard !file.isEmpty, let members = grouped[file]?.sorted(by: rankedOrder), !members.isEmpty else {
                return nil
            }
            let evidence = members.flatMap { $0.item.evidence }.sorted(by: evidenceOrder)
            let anchor = members[0].item.entity.location
            return DebtAggregation(
                id: "file:\(file)",
                level: .file,
                displayName: file,
                location: DebtLocation(module: anchor.module, file: file, line: anchor.line, column: anchor.column),
                memberItemIDs: members.map { $0.item.id }.sorted(),
                score: scoring.score(evidence: evidence)
            )
        }
    }
}

private func rankedOrder(_ lhs: RankedDebtItem, _ rhs: RankedDebtItem) -> Bool {
    switch (lhs.score.value, rhs.score.value) {
    case (.some(let left), .some(let right)) where left != right:
        return left > right
    case (.some, .none):
        return true
    case (.none, .some):
        return false
    default:
        // A single scoring policy derives priority from score, so equal or nil scores
        // cannot have different priorities.
        return lhs.item.id < rhs.item.id
    }
}

private func evidenceOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
    return lhs.rawValue < rhs.rawValue
}

private func priorityRank(_ priority: Priority) -> Int {
    switch priority {
    case .low: 0
    case .medium: 1
    case .high: 2
    case .critical: 3
    }
}

private func category(for item: DebtItem) -> String {
    let kinds = item.evidence.map(\.kind).sorted()
    guard let first = kinds.first else { return "uncategorized" }
    return first.split(separator: ".", maxSplits: 1).first.map(String.init) ?? first
}

private func explanation(for item: DebtItem) -> String {
    guard
        let strongest = item.evidence.max(by: { lhs, rhs in
            if (lhs.normalizedScore ?? -1) != (rhs.normalizedScore ?? -1) {
                return (lhs.normalizedScore ?? -1) < (rhs.normalizedScore ?? -1)
            }
            return lhs.id > rhs.id
        })
    else {
        return "No evidence was available for this debt item."
    }
    return "Highest evidence is \(strongest.kind) with raw value \(strongest.rawValue). \(strongest.note ?? "")"
}

private func recommendation(for item: DebtItem) -> String {
    if item.evidence.contains(where: { !$0.availability.isAvailable }) {
        return
            "Review unavailable evidence before treating the score as complete; no unavailable provider was converted to zero risk."
    }
    if item.evidence.contains(where: { $0.kind.hasPrefix("coverage.") }) {
        return
            "Prioritize tests around this context before structural refactoring; coverage evidence can only dampen risk."
    }
    switch item.entity.level {
    case .callable:
        return "Reduce the dominant callable risk while preserving behavior with focused tests."
    case .type:
        return "Split responsibilities or simplify the most complex methods in this type."
    case .file:
        return "Inspect clustered callable and type evidence before moving code across file boundaries."
    case .module:
        return "Review module boundaries and repeated high-risk files before broad refactoring."
    }
}
