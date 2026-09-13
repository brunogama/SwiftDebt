import SCMACore

package struct DebtReportProjectionBuilder {
    package init() {}

    package func nativeReport(from analysis: RankedDebtAnalysis) -> DebtReport {
        let items = sorted(analysis.items).map { ranked in
            DebtReportItem(
                id: ranked.item.id,
                displayName: ranked.item.entity.displayName,
                level: ranked.item.entity.level,
                location: ranked.item.entity.location,
                category: ranked.category,
                score: ranked.score.value,
                priority: ranked.score.priority,
                explanation: ranked.explanation,
                recommendation: ranked.recommendation,
                evidence: sortedEvidence(ranked.item.evidence),
                scoreBreakdown: sortedBreakdown(ranked.score.breakdown)
            )
        }
        return DebtReport(
            options: analysis.options,
            summary: analysis.summary,
            items: items,
            aggregations: aggregations(from: analysis),
            compactItems: compactItems(from: analysis),
            missingEvidence: missingEvidence(from: analysis)
        )
    }

    package func projection(from analysis: RankedDebtAnalysis) -> DebtmapCompatibilityProjection {
        DebtmapCompatibilityProjection(
            items: sorted(analysis.items).map { ranked in
                DebtmapCompatibilityItem(
                    id: ranked.item.id,
                    entity: ranked.item.entity.displayName,
                    level: ranked.item.entity.level,
                    location: ranked.item.entity.location,
                    priority: ranked.score.priority,
                    score: ranked.score.value,
                    evidenceKinds: Array(Set(ranked.item.evidence.map(\.kind))).sorted(),
                    action: ranked.recommendation
                )
            },
            missingEvidence: missingEvidence(from: analysis)
        )
    }

    private func aggregations(from analysis: RankedDebtAnalysis) -> [DebtReportAggregation] {
        analysis.aggregations.sorted { lhs, rhs in
            if lhs.level.rawValue != rhs.level.rawValue { return lhs.level.rawValue < rhs.level.rawValue }
            return lhs.id < rhs.id
        }.map { aggregation in
            DebtReportAggregation(
                id: aggregation.id,
                level: aggregation.level,
                displayName: aggregation.displayName,
                location: aggregation.location,
                memberItemIDs: aggregation.memberItemIDs.sorted(),
                score: aggregation.score?.value,
                priority: aggregation.score?.priority
            )
        }
    }

    private func compactItems(from analysis: RankedDebtAnalysis) -> [CompactDebtItem] {
        analysis.compactItems.sorted { lhs, rhs in
            itemOrder(
                lhsID: lhs.id,
                lhsScore: lhs.score,
                lhsPriority: lhs.priority,
                rhsID: rhs.id,
                rhsScore: rhs.score,
                rhsPriority: rhs.priority
            )
        }
    }

    private func missingEvidence(from analysis: RankedDebtAnalysis) -> [DebtReportMissingEvidence] {
        sorted(analysis.items).flatMap { ranked in
            ranked.score.breakdown.unavailableEvidence.map { evidence in
                DebtReportMissingEvidence(
                    itemID: ranked.item.id,
                    evidenceID: evidence.evidenceID,
                    kind: evidence.kind,
                    requirement: evidence.requirement,
                    configuredWeight: evidence.configuredWeight,
                    reason: evidence.reason ?? "unspecified"
                )
            }
        }.sorted { lhs, rhs in
            if lhs.itemID != rhs.itemID { return lhs.itemID < rhs.itemID }
            if lhs.evidenceID != rhs.evidenceID { return lhs.evidenceID < rhs.evidenceID }
            return lhs.kind < rhs.kind
        }
    }

    private func sorted(_ items: [RankedDebtItem]) -> [RankedDebtItem] {
        items.sorted { lhs, rhs in
            itemOrder(
                lhsID: lhs.item.id,
                lhsScore: lhs.score.value,
                lhsPriority: lhs.score.priority,
                rhsID: rhs.item.id,
                rhsScore: rhs.score.value,
                rhsPriority: rhs.score.priority
            )
        }
    }

    private func itemOrder(
        lhsID: String,
        lhsScore: Double?,
        lhsPriority: Priority?,
        rhsID: String,
        rhsScore: Double?,
        rhsPriority: Priority?
    ) -> Bool {
        switch (lhsScore, rhsScore) {
        case let (lhs?, rhs?) where lhs != rhs:
            return lhs > rhs
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        default:
            break
        }
        let lhsPriorityValue = lhsPriority.map(priorityRank) ?? -1
        let rhsPriorityValue = rhsPriority.map(priorityRank) ?? -1
        if lhsPriorityValue != rhsPriorityValue { return lhsPriorityValue > rhsPriorityValue }
        return lhsID < rhsID
    }

    private func sortedEvidence(_ evidence: [DebtEvidence]) -> [DebtEvidence] {
        evidence.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            return lhs.rawValue < rhs.rawValue
        }
    }

    private func sortedBreakdown(_ breakdown: DebtScoreBreakdown) -> DebtScoreBreakdown {
        DebtScoreBreakdown(
            totalConfiguredWeight: breakdown.totalConfiguredWeight,
            totalAvailableWeight: breakdown.totalAvailableWeight,
            contributions: breakdown.contributions.sorted { lhs, rhs in
                if lhs.evidenceID != rhs.evidenceID { return lhs.evidenceID < rhs.evidenceID }
                return lhs.kind < rhs.kind
            },
            unavailableEvidence: breakdown.unavailableEvidence.sorted { lhs, rhs in
                if lhs.evidenceID != rhs.evidenceID { return lhs.evidenceID < rhs.evidenceID }
                return lhs.kind < rhs.kind
            }
        )
    }

    private func priorityRank(_ priority: Priority) -> Int {
        switch priority {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .critical: 3
        }
    }
}
