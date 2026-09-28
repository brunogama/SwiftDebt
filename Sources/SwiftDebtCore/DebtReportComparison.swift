extension DebtReportComparator {
    package func validateSchema(_ schemaVersion: Int, label: String) throws {
        guard schemaVersion == DebtReportSchema.currentVersion else {
            throw AnalysisFailure.invalidConfiguration(
                "Unsupported \(label) debt report schema version \(schemaVersion); expected \(DebtReportSchema.currentVersion)"
            )
        }
    }

    package func changedItem(before: DebtReportItem, after: DebtReportItem)
        -> DebtReportChangedItem?
    {
        let evidence = setDelta(before: evidenceIDs(before), after: evidenceIDs(after))
        let unavailableEvidence = setDelta(
            before: unavailableEvidenceIDs(before), after: unavailableEvidenceIDs(after))
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

    package func changedAggregation(
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

    package func snapshot(_ aggregation: DebtReportAggregation) -> DebtReportAggregationSnapshot {
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

    package func evidenceIDs(_ item: DebtReportItem) -> [String] {
        item.evidence.map(\.id).sorted()
    }

    package func unavailableEvidenceIDs(_ item: DebtReportItem) -> [String] {
        item.scoreBreakdown.unavailableEvidence.map(\.evidenceID).sorted()
    }

    package func missingEvidenceIDs(_ report: DebtReport) -> [String] {
        report.missingEvidence.map { "\($0.itemID):\($0.evidenceID)" }.sorted()
    }

    package func totalScore(_ items: [DebtReportItem]) -> Double {
        items.reduce(0) { total, item in total + (item.score ?? 0) }
    }

    package func doubleDelta(before: Double?, after: Double?) -> DebtDoubleDelta {
        let delta: Double?
        if let before, let after {
            delta = after - before
        } else {
            delta = nil
        }
        return DebtDoubleDelta(before: before, after: after, delta: delta)
    }

    package func setDelta(before: [String], after: [String]) -> DebtStringSetDelta {
        let beforeSet = Set(before)
        let afterSet = Set(after)
        return DebtStringSetDelta(
            added: Array(afterSet.subtracting(beforeSet)).sorted(),
            removed: Array(beforeSet.subtracting(afterSet)).sorted()
        )
    }

    package func dictionary<T>(_ values: [T], by keyPath: KeyPath<T, String>) -> [String: T] {
        var result: [String: T] = [:]
        for value in values {
            result[value[keyPath: keyPath]] = value
        }
        return result
    }
}
