public struct DebtReportComparator: Sendable {
    public init() {}

    public func compare(before: DebtReport, after: DebtReport) throws -> DebtReportComparison {
        try validateSchema(before.schemaVersion, label: "before")
        try validateSchema(after.schemaVersion, label: "after")

        let beforeItems = dictionary(before.items, by: \.id)
        let afterItems = dictionary(after.items, by: \.id)
        let beforeItemIDs = Set(beforeItems.keys)
        let afterItemIDs = Set(afterItems.keys)
        let addedItemIDs = Array(afterItemIDs.subtracting(beforeItemIDs)).sorted()
        let removedItemIDs = Array(beforeItemIDs.subtracting(afterItemIDs)).sorted()
        let commonItemIDs = Array(beforeItemIDs.intersection(afterItemIDs)).sorted()

        let addedItems = addedItemIDs.map { snapshot(afterItems[$0]!) }
        let removedItems = removedItemIDs.map { snapshot(beforeItems[$0]!) }
        var changedItems: [DebtReportChangedItem] = []
        var unchangedItemIDs: [String] = []
        for id in commonItemIDs {
            let beforeItem = beforeItems[id]!
            let afterItem = afterItems[id]!
            if let change = changedItem(before: beforeItem, after: afterItem) {
                changedItems.append(change)
            } else {
                unchangedItemIDs.append(id)
            }
        }

        let beforeAggregations = dictionary(before.aggregations, by: \.id)
        let afterAggregations = dictionary(after.aggregations, by: \.id)
        let beforeAggregationIDs = Set(beforeAggregations.keys)
        let afterAggregationIDs = Set(afterAggregations.keys)
        let addedAggregationIDs = Array(afterAggregationIDs.subtracting(beforeAggregationIDs)).sorted()
        let removedAggregationIDs = Array(beforeAggregationIDs.subtracting(afterAggregationIDs)).sorted()
        let commonAggregationIDs = Array(beforeAggregationIDs.intersection(afterAggregationIDs)).sorted()

        let addedAggregations = addedAggregationIDs.map { snapshot(afterAggregations[$0]!) }
        let removedAggregations = removedAggregationIDs.map { snapshot(beforeAggregations[$0]!) }
        var changedAggregations: [DebtReportChangedAggregation] = []
        var unchangedAggregationIDs: [String] = []
        for id in commonAggregationIDs {
            let beforeAggregation = beforeAggregations[id]!
            let afterAggregation = afterAggregations[id]!
            if let change = changedAggregation(before: beforeAggregation, after: afterAggregation) {
                changedAggregations.append(change)
            } else {
                unchangedAggregationIDs.append(id)
            }
        }

        let beforeTotalScore = totalScore(before.items)
        let afterTotalScore = totalScore(after.items)
        let missingEvidence = setDelta(before: missingEvidenceIDs(before), after: missingEvidenceIDs(after))
        let summary = DebtReportComparisonSummary(
            beforeItemCount: before.items.count,
            afterItemCount: after.items.count,
            addedItemCount: addedItems.count,
            removedItemCount: removedItems.count,
            changedItemCount: changedItems.count,
            unchangedItemCount: unchangedItemIDs.count,
            beforeTotalScore: beforeTotalScore,
            afterTotalScore: afterTotalScore,
            totalScoreDelta: afterTotalScore - beforeTotalScore,
            beforeUnavailableEvidenceCount: before.summary.unavailableEvidenceCount,
            afterUnavailableEvidenceCount: after.summary.unavailableEvidenceCount,
            unavailableEvidenceDelta: after.summary.unavailableEvidenceCount - before.summary.unavailableEvidenceCount,
            addedAggregationCount: addedAggregations.count,
            removedAggregationCount: removedAggregations.count,
            changedAggregationCount: changedAggregations.count
        )
        return DebtReportComparison(
            schemaVersion: DebtReportComparisonSchema.currentVersion,
            beforeReportSchemaVersion: before.schemaVersion,
            afterReportSchemaVersion: after.schemaVersion,
            summary: summary,
            itemChanges: DebtReportItemChanges(
                added: addedItems,
                removed: removedItems,
                changed: changedItems,
                unchangedIDs: unchangedItemIDs
            ),
            aggregationChanges: DebtReportAggregationChanges(
                added: addedAggregations,
                removed: removedAggregations,
                changed: changedAggregations,
                unchangedIDs: unchangedAggregationIDs
            ),
            missingEvidence: missingEvidence
        )
    }

    private func validateSchema(_ schemaVersion: Int, label: String) throws {
        guard schemaVersion == DebtReportSchema.currentVersion else {
            throw AnalysisFailure.invalidConfiguration(
                "Unsupported \(label) debt report schema version \(schemaVersion); expected \(DebtReportSchema.currentVersion)"
            )
        }
    }

    private func changedItem(before: DebtReportItem, after: DebtReportItem) -> DebtReportChangedItem? {
        let evidence = setDelta(before: evidenceIDs(before), after: evidenceIDs(after))
        let unavailableEvidence = setDelta(before: unavailableEvidenceIDs(before), after: unavailableEvidenceIDs(after))
        let moved = before.location != after.location
        guard
            moved || before.score != after.score || before.priority != after.priority
                || !evidence.added.isEmpty || !evidence.removed.isEmpty
                || !unavailableEvidence.added.isEmpty || !unavailableEvidence.removed.isEmpty
        else { return nil }
        return DebtReportChangedItem(
            id: before.id,
            displayName: after.displayName,
            moved: moved,
            beforeLocation: before.location,
            afterLocation: after.location,
            score: doubleDelta(before: before.score, after: after.score),
            priority: DebtPriorityDelta(before: before.priority, after: after.priority),
            evidence: evidence,
            unavailableEvidence: unavailableEvidence
        )
    }

    private func changedAggregation(
        before: DebtReportAggregation,
        after: DebtReportAggregation
    ) -> DebtReportChangedAggregation? {
        let memberItems = setDelta(before: before.memberItemIDs, after: after.memberItemIDs)
        let moved = before.location != after.location
        guard
            moved || before.score != after.score || before.priority != after.priority
                || !memberItems.added.isEmpty || !memberItems.removed.isEmpty
        else { return nil }
        return DebtReportChangedAggregation(
            id: before.id,
            displayName: after.displayName,
            level: after.level,
            moved: moved,
            beforeLocation: before.location,
            afterLocation: after.location,
            score: doubleDelta(before: before.score, after: after.score),
            priority: DebtPriorityDelta(before: before.priority, after: after.priority),
            memberItemIDs: memberItems
        )
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

    private func snapshot(_ aggregation: DebtReportAggregation) -> DebtReportAggregationSnapshot {
        DebtReportAggregationSnapshot(
            id: aggregation.id,
            displayName: aggregation.displayName,
            level: aggregation.level,
            location: aggregation.location,
            memberItemIDs: aggregation.memberItemIDs.sorted(),
            score: aggregation.score,
            priority: aggregation.priority
        )
    }

    private func evidenceIDs(_ item: DebtReportItem) -> [String] {
        item.evidence.map(\.id).sorted()
    }

    private func unavailableEvidenceIDs(_ item: DebtReportItem) -> [String] {
        item.scoreBreakdown.unavailableEvidence.map(\.evidenceID).sorted()
    }

    private func missingEvidenceIDs(_ report: DebtReport) -> [String] {
        report.missingEvidence.map { "\($0.itemID):\($0.evidenceID)" }.sorted()
    }

    private func totalScore(_ items: [DebtReportItem]) -> Double {
        items.reduce(0) { total, item in total + (item.score ?? 0) }
    }

    private func doubleDelta(before: Double?, after: Double?) -> DebtDoubleDelta {
        let delta: Double?
        if let before, let after {
            delta = after - before
        } else {
            delta = nil
        }
        return DebtDoubleDelta(before: before, after: after, delta: delta)
    }

    private func setDelta(before: [String], after: [String]) -> DebtStringSetDelta {
        let beforeSet = Set(before)
        let afterSet = Set(after)
        return DebtStringSetDelta(
            added: Array(afterSet.subtracting(beforeSet)).sorted(),
            removed: Array(beforeSet.subtracting(afterSet)).sorted()
        )
    }

    private func dictionary<T>(_ values: [T], by keyPath: KeyPath<T, String>) -> [String: T] {
        var result: [String: T] = [:]
        for value in values {
            result[value[keyPath: keyPath]] = value
        }
        return result
    }
}
