import Foundation
import SwiftDebtCore

extension RepositorySyntaxFactCache {
    func incrementallyResolve(
        sources: [SourceUnit],
        sourceSnapshotDigest: RepositoryDigest,
        compatibility: RepositorySyntaxCacheCompatibility,
        retained: RepositorySyntaxCacheDocument,
        existingData: Data,
        url: URL
    ) throws -> Resolution {
        let retainedByPath = Dictionary(uniqueKeysWithValues: retained.entries.map { ($0.path, $0) })
        let selectedPaths = Set(sources.map(\.path))
        let removedCount = retained.entries.count { !selectedPaths.contains($0.path) }
        var invalidationCounts: [RepositorySyntaxCacheInvalidationReason: Int] = [:]
        if removedCount > 0 { invalidationCounts[.sourceRemoved] = removedCount }
        var budget = RepositorySyntaxFactBudget(
            maximumAnalysisUnitsPerRule: compatibility.maximumAnalysisUnitsPerRule
        )
        var entries: [RepositorySyntaxCacheEntry] = []
        var facts = RepositorySyntaxFacts()
        var reusedCount = 0
        for source in sources {
            let digest = try sourceDigest(source)
            let retainedEntry = retainedByPath[source.path]
            let invalidation = invalidationReason(
                source: source,
                digest: digest,
                incomingBudget: budget,
                retained: retainedEntry
            )
            let sourceFacts: RepositorySyntaxFacts
            if invalidation == nil, let retainedEntry {
                sourceFacts = retainedEntry.facts
                reusedCount += 1
            } else {
                sourceFacts = RepositorySyntaxExtractor().extract(
                    source,
                    maximumDataClumpUnits: budget.dataClumpUnits,
                    maximumRepeatedSwitchFacts: budget.repeatedSwitchFacts
                )
                invalidationCounts[invalidation ?? .sourceAdded, default: 0] += 1
            }
            entries.append(
                RepositorySyntaxCacheEntry(
                    path: source.path,
                    module: source.module,
                    contentDigest: digest,
                    incomingBudget: budget,
                    facts: sourceFacts
                )
            )
            facts.append(sourceFacts)
            budget = try budget.consuming(sourceFacts)
        }
        facts.sortCanonical()
        let document = try RepositorySyntaxCacheDocument(
            sourceSnapshotDigest: sourceSnapshotDigest,
            compatibility: compatibility,
            entries: entries
        )
        let persisted = try RepositorySyntaxCacheStore().persist(
            document,
            to: url,
            existingData: existingData,
            forceWrite: false
        )
        let recomputedCount = sources.count - reusedCount
        let disposition: RepositorySyntaxCacheDisposition =
            recomputedCount == 0 && removedCount == 0 ? .warmReuse : .partialRebuild
        let invalidations = invalidationCounts.map {
            RepositorySyntaxCacheInvalidation(reason: $0.key, sourceCount: $0.value)
        }
        return Resolution(
            facts: facts,
            report: report(
                mode: .reuse,
                disposition: disposition,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url,
                persisted: persisted,
                selectedCount: sources.count,
                reusedCount: reusedCount,
                recomputedCount: recomputedCount,
                removedCount: removedCount,
                invalidations: invalidations
            )
        )
    }

    func extractAll(
        _ sources: [SourceUnit],
        sourceSnapshotDigest: RepositoryDigest,
        compatibility: RepositorySyntaxCacheCompatibility
    ) throws -> (document: RepositorySyntaxCacheDocument, facts: RepositorySyntaxFacts) {
        var budget = RepositorySyntaxFactBudget(
            maximumAnalysisUnitsPerRule: compatibility.maximumAnalysisUnitsPerRule
        )
        var entries: [RepositorySyntaxCacheEntry] = []
        var facts = RepositorySyntaxFacts()
        for source in sources {
            let sourceFacts = RepositorySyntaxExtractor().extract(
                source,
                maximumDataClumpUnits: budget.dataClumpUnits,
                maximumRepeatedSwitchFacts: budget.repeatedSwitchFacts
            )
            entries.append(
                RepositorySyntaxCacheEntry(
                    path: source.path,
                    module: source.module,
                    contentDigest: try sourceDigest(source),
                    incomingBudget: budget,
                    facts: sourceFacts
                )
            )
            facts.append(sourceFacts)
            budget = try budget.consuming(sourceFacts)
        }
        facts.sortCanonical()
        return (
            try RepositorySyntaxCacheDocument(
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                entries: entries
            ),
            facts
        )
    }

    func invalidationReason(
        source: SourceUnit,
        digest: RepositoryDigest,
        incomingBudget: RepositorySyntaxFactBudget,
        retained: RepositorySyntaxCacheEntry?
    ) -> RepositorySyntaxCacheInvalidationReason? {
        guard let retained else { return .sourceAdded }
        if retained.module != source.module { return .sourceMetadataChanged }
        if retained.contentDigest != digest { return .sourceContentChanged }
        if retained.incomingBudget != incomingBudget { return .dependencyChanged }
        return nil
    }

    func sourceDigest(_ source: SourceUnit) throws -> RepositoryDigest {
        var hasher = RepositorySHA256()
        hasher.updateFramed("swiftdebt-repository-source-content-v1")
        hasher.updateFramed(source.content)
        return try RepositoryDigest(value: hasher.finalizeHex())
    }
}
