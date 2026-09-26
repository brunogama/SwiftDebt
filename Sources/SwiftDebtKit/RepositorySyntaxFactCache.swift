import Foundation
import SwiftDebtCore

struct RepositorySyntaxFactCache {
    struct Resolution {
        let facts: RepositorySyntaxFacts
        let report: RepositorySyntaxCacheReport
    }

    func resolve(
        sources: [SourceUnit],
        sourceSnapshotDigest: RepositoryDigest,
        configuration: RepositoryAnalysisConfiguration,
        policy: RepositorySyntaxCachePolicy
    ) throws -> Resolution {
        let compatibility = RepositorySyntaxCacheCompatibility.current(configuration: configuration)
        switch policy {
        case .disabled:
            let facts = RepositorySyntaxExtractor().extract(
                sources,
                maximumAnalysisUnitsPerRule: configuration.maximumAnalysisUnitsPerRule
            )
            return Resolution(
                facts: facts,
                report: RepositorySyntaxCacheReport(
                    sourceSnapshotDigest: sourceSnapshotDigest,
                    mode: .disabled,
                    disposition: .disabled,
                    compatibility: compatibility,
                    storage: RepositorySyntaxCacheStorage(
                        location: nil,
                        dataClasses: [],
                        byteCount: 0,
                        contentDigest: nil,
                        writePerformed: false
                    ),
                    selectedSourceCount: sources.count,
                    reusedSourceCount: 0,
                    recomputedSourceCount: sources.count,
                    removedSourceCount: 0,
                    invalidations: [
                        RepositorySyntaxCacheInvalidation(
                            reason: .cacheDisabled,
                            sourceCount: sources.count
                        )
                    ]
                )
            )
        case .rebuild(let url):
            return try rebuild(
                sources: sources,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url,
                mode: .rebuild,
                disposition: .forcedRebuild,
                reasons: [.forcedRebuild],
                forceWrite: true
            )
        case .reuse(let url):
            return try reuse(
                sources: sources,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url
            )
        }
    }

    private func reuse(
        sources: [SourceUnit],
        sourceSnapshotDigest: RepositoryDigest,
        compatibility: RepositorySyntaxCacheCompatibility,
        url: URL
    ) throws -> Resolution {
        let store = RepositorySyntaxCacheStore()
        switch try store.load(from: url, compatibility: compatibility) {
        case .missing:
            return try rebuild(
                sources: sources,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url,
                mode: .reuse,
                disposition: .coldRebuild,
                reasons: [.cacheMissing],
                forceWrite: true
            )
        case .corrupt:
            return try rebuild(
                sources: sources,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url,
                mode: .reuse,
                disposition: .recoveredCorruption,
                reasons: [.cacheCorrupt],
                forceWrite: true
            )
        case .schemaMismatch:
            return try rebuild(
                sources: sources,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url,
                mode: .reuse,
                disposition: .incompatibleRebuild,
                reasons: [.schemaMismatch],
                forceWrite: true
            )
        case .incompatible(let reasons):
            return try rebuild(
                sources: sources,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url,
                mode: .reuse,
                disposition: .incompatibleRebuild,
                reasons: reasons,
                forceWrite: true
            )
        case .compatible(let document, let existingData):
            return try incrementallyResolve(
                sources: sources,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                retained: document,
                existingData: existingData,
                url: url
            )
        }
    }

    private func rebuild(
        sources: [SourceUnit],
        sourceSnapshotDigest: RepositoryDigest,
        compatibility: RepositorySyntaxCacheCompatibility,
        url: URL,
        mode: RepositorySyntaxCacheMode,
        disposition: RepositorySyntaxCacheDisposition,
        reasons: [RepositorySyntaxCacheInvalidationReason],
        forceWrite: Bool
    ) throws -> Resolution {
        let extraction = try extractAll(
            sources,
            sourceSnapshotDigest: sourceSnapshotDigest,
            compatibility: compatibility
        )
        let persisted = try RepositorySyntaxCacheStore().persist(
            extraction.document,
            to: url,
            existingData: nil,
            forceWrite: forceWrite
        )
        return Resolution(
            facts: extraction.facts,
            report: report(
                mode: mode,
                disposition: disposition,
                sourceSnapshotDigest: sourceSnapshotDigest,
                compatibility: compatibility,
                url: url,
                persisted: persisted,
                selectedCount: sources.count,
                reusedCount: 0,
                recomputedCount: sources.count,
                removedCount: 0,
                invalidations: reasons.map {
                    RepositorySyntaxCacheInvalidation(reason: $0, sourceCount: sources.count)
                }
            )
        )
    }
}
