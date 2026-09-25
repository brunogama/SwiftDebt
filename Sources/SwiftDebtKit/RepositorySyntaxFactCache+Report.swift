import Foundation
import SwiftDebtCore

extension RepositorySyntaxFactCache {
    func report(
        mode: RepositorySyntaxCacheMode,
        disposition: RepositorySyntaxCacheDisposition,
        sourceSnapshotDigest: RepositoryDigest,
        compatibility: RepositorySyntaxCacheCompatibility,
        url: URL,
        persisted: RepositorySyntaxCacheStore.PersistenceResult,
        selectedCount: Int,
        reusedCount: Int,
        recomputedCount: Int,
        removedCount: Int,
        invalidations: [RepositorySyntaxCacheInvalidation]
    ) -> RepositorySyntaxCacheReport {
        RepositorySyntaxCacheReport(
            sourceSnapshotDigest: sourceSnapshotDigest,
            mode: mode,
            disposition: disposition,
            compatibility: compatibility,
            storage: RepositorySyntaxCacheStorage(
                location: url.path,
                dataClasses: RepositorySyntaxCacheStore.retainedDataClasses,
                byteCount: persisted.data.count,
                contentDigest: persisted.digest,
                writePerformed: persisted.writePerformed
            ),
            selectedSourceCount: selectedCount,
            reusedSourceCount: reusedCount,
            recomputedSourceCount: recomputedCount,
            removedSourceCount: removedCount,
            invalidations: invalidations
        )
    }
}
