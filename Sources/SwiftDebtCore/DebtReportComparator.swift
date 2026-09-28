private struct ComparedItems {
    let added: [DebtReportItemSnapshot]
    let removed: [DebtReportItemSnapshot]
    let changed: [DebtReportChangedItem]
    let unchangedIDs: [String]
}

private struct ComparedAggregations {
    let added: [DebtReportAggregationSnapshot]
    let removed: [DebtReportAggregationSnapshot]
    let changed: [DebtReportChangedAggregation]
    let unchangedIDs: [String]
}

public struct DebtReportComparator: Sendable {
    public init() {}

    public func compare(before: DebtReport, after: DebtReport) throws -> DebtReportComparison {
        try validateSchema(before.schemaVersion, label: "before")
        try validateSchema(after.schemaVersion, label: "after")

        let items = compareItems(before: before.items, after: after.items)
        let aggregations = compareAggregations(
            before: before.aggregations, after: after.aggregations)
        let missingEvidence = setDelta(
            before: missingEvidenceIDs(before), after: missingEvidenceIDs(after))
        return DebtReportComparison(
            schemaVersion: DebtReportComparisonSchema.currentVersion,
            beforeReportSchemaVersion: before.schemaVersion,
            afterReportSchemaVersion: after.schemaVersion,
            summary: comparisonSummary(
                before: before, after: after, items: items, aggregations: aggregations),
            itemChanges: DebtReportItemChanges(
                added: items.added, removed: items.removed, changed: items.changed,
                unchangedIDs: items.unchangedIDs
            ),
            aggregationChanges: DebtReportAggregationChanges(
                added: aggregations.added, removed: aggregations.removed,
                changed: aggregations.changed, unchangedIDs: aggregations.unchangedIDs
            ),
            missingEvidence: missingEvidence
        )
    }

    private func compareItems(before: [DebtReportItem], after: [DebtReportItem]) -> ComparedItems {
        let beforeByID = dictionary(before, by: \.id)
        let afterByID = dictionary(after, by: \.id)
        let beforeIDs = Set(beforeByID.keys)
        let afterIDs = Set(afterByID.keys)
        let added = afterIDs.subtracting(beforeIDs).sorted().map { snapshot(afterByID[$0]!) }
        let removed = beforeIDs.subtracting(afterIDs).sorted().map { snapshot(beforeByID[$0]!) }
        var changed: [DebtReportChangedItem] = []
        var unchangedIDs: [String] = []
        for id in beforeIDs.intersection(afterIDs).sorted() {
            if let change = changedItem(before: beforeByID[id]!, after: afterByID[id]!) {
                changed.append(change)
            } else {
                unchangedIDs.append(id)
            }
        }
        return ComparedItems(
            added: added, removed: removed, changed: changed, unchangedIDs: unchangedIDs)
    }

    private func compareAggregations(
        before: [DebtReportAggregation], after: [DebtReportAggregation]
    ) -> ComparedAggregations {
        let beforeByID = dictionary(before, by: \.id)
        let afterByID = dictionary(after, by: \.id)
        let beforeIDs = Set(beforeByID.keys)
        let afterIDs = Set(afterByID.keys)
        let added = afterIDs.subtracting(beforeIDs).sorted().map { snapshot(afterByID[$0]!) }
        let removed = beforeIDs.subtracting(afterIDs).sorted().map { snapshot(beforeByID[$0]!) }
        var changed: [DebtReportChangedAggregation] = []
        var unchangedIDs: [String] = []
        for id in beforeIDs.intersection(afterIDs).sorted() {
            if let change = changedAggregation(before: beforeByID[id]!, after: afterByID[id]!) {
                changed.append(change)
            } else {
                unchangedIDs.append(id)
            }
        }
        return ComparedAggregations(
            added: added, removed: removed, changed: changed, unchangedIDs: unchangedIDs)
    }

    private func comparisonSummary(
        before: DebtReport, after: DebtReport, items: ComparedItems,
        aggregations: ComparedAggregations
    ) -> DebtReportComparisonSummary {
        let beforeTotalScore = totalScore(before.items)
        let afterTotalScore = totalScore(after.items)
        return DebtReportComparisonSummary(
            beforeItemCount: before.items.count, afterItemCount: after.items.count,
            addedItemCount: items.added.count, removedItemCount: items.removed.count,
            changedItemCount: items.changed.count, unchangedItemCount: items.unchangedIDs.count,
            beforeTotalScore: beforeTotalScore, afterTotalScore: afterTotalScore,
            totalScoreDelta: afterTotalScore - beforeTotalScore,
            beforeUnavailableEvidenceCount: before.summary.unavailableEvidenceCount,
            afterUnavailableEvidenceCount: after.summary.unavailableEvidenceCount,
            unavailableEvidenceDelta: after.summary.unavailableEvidenceCount
                - before.summary.unavailableEvidenceCount,
            addedAggregationCount: aggregations.added.count,
            removedAggregationCount: aggregations.removed.count,
            changedAggregationCount: aggregations.changed.count)
    }

    private func snapshot(_ item: DebtReportItem) -> DebtReportItemSnapshot {
        DebtReportItemSnapshot(
            id: item.id,
            displayName: item.displayName,
            level: item.level,
            location: item.location,
            score: item.score,
            priority: item.priority,
            evidenceIDs: evidenceIDs(item),
            unavailableEvidenceIDs: unavailableEvidenceIDs(item)
        )
    }

}
