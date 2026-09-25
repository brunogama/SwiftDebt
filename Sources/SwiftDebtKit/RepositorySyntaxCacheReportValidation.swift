import Foundation

func cacheReportIsValid(
    mode: RepositorySyntaxCacheMode,
    disposition: RepositorySyntaxCacheDisposition,
    compatibility: RepositorySyntaxCacheCompatibility,
    storage: RepositorySyntaxCacheStorage,
    selectedSourceCount: Int,
    reusedSourceCount: Int,
    recomputedSourceCount: Int,
    removedSourceCount: Int,
    invalidations: [RepositorySyntaxCacheInvalidation],
    networkRequestCount: Int
) -> Bool {
    guard
        let processedSourceCount = sumWithoutOverflow([
            reusedSourceCount,
            recomputedSourceCount,
        ])
    else { return false }
    guard (try? compatibility.validateCanonicalForm()) != nil,
        selectedSourceCount > 0,
        reusedSourceCount >= 0,
        recomputedSourceCount >= 0,
        removedSourceCount >= 0,
        processedSourceCount == selectedSourceCount,
        networkRequestCount == 0,
        invalidations == invalidations.sorted(by: { $0.reason.rawValue < $1.reason.rawValue }),
        Set(invalidations.map(\.reason)).count == invalidations.count,
        invalidations.allSatisfy({ $0.sourceCount > 0 })
    else { return false }

    let storageIsEnabled = cacheStorageIsEnabled(storage)
    switch (mode, disposition) {
    case (.disabled, .disabled):
        return cacheStorageIsDisabled(storage)
            && reusedSourceCount == 0
            && recomputedSourceCount == selectedSourceCount
            && removedSourceCount == 0
            && invalidations == [
                RepositorySyntaxCacheInvalidation(
                    reason: .cacheDisabled,
                    sourceCount: selectedSourceCount
                )
            ]
    case (.rebuild, .forcedRebuild):
        return storageIsEnabled
            && storage.writePerformed
            && reusedSourceCount == 0
            && recomputedSourceCount == selectedSourceCount
            && removedSourceCount == 0
            && invalidations == [
                RepositorySyntaxCacheInvalidation(
                    reason: .forcedRebuild,
                    sourceCount: selectedSourceCount
                )
            ]
    case (.reuse, .coldRebuild):
        return fullRebuildIsValid(
            storage: storage,
            selectedSourceCount: selectedSourceCount,
            reusedSourceCount: reusedSourceCount,
            recomputedSourceCount: recomputedSourceCount,
            removedSourceCount: removedSourceCount,
            invalidations: invalidations,
            expectedReasons: [.cacheMissing]
        )
    case (.reuse, .recoveredCorruption):
        return fullRebuildIsValid(
            storage: storage,
            selectedSourceCount: selectedSourceCount,
            reusedSourceCount: reusedSourceCount,
            recomputedSourceCount: recomputedSourceCount,
            removedSourceCount: removedSourceCount,
            invalidations: invalidations,
            expectedReasons: [.cacheCorrupt]
        )
    case (.reuse, .incompatibleRebuild):
        let allowed: Set<RepositorySyntaxCacheInvalidationReason> = [
            .schemaMismatch,
            .factSchemaMismatch,
            .projectionChanged,
            .providerChanged,
            .ruleSemanticsChanged,
            .configurationChanged,
        ]
        return fullRebuildIsValid(
            storage: storage,
            selectedSourceCount: selectedSourceCount,
            reusedSourceCount: reusedSourceCount,
            recomputedSourceCount: recomputedSourceCount,
            removedSourceCount: removedSourceCount,
            invalidations: invalidations,
            expectedReasons: allowed
        )
    case (.reuse, .warmReuse):
        return storageIsEnabled
            && !storage.writePerformed
            && reusedSourceCount == selectedSourceCount
            && recomputedSourceCount == 0
            && removedSourceCount == 0
            && invalidations.isEmpty
    case (.reuse, .partialRebuild):
        let allowed: Set<RepositorySyntaxCacheInvalidationReason> = [
            .sourceAdded,
            .sourceContentChanged,
            .sourceMetadataChanged,
            .dependencyChanged,
            .sourceRemoved,
        ]
        guard
            let selectedInvalidationCount = sumWithoutOverflow(
                invalidations
                    .filter { $0.reason != .sourceRemoved }
                    .map(\.sourceCount)
            )
        else { return false }
        let removedInvalidationCount =
            invalidations
            .first { $0.reason == .sourceRemoved }?.sourceCount ?? 0
        return storageIsEnabled
            && storage.writePerformed
            && (recomputedSourceCount > 0 || removedSourceCount > 0)
            && Set(invalidations.map(\.reason)).isSubset(of: allowed)
            && selectedInvalidationCount == recomputedSourceCount
            && removedInvalidationCount == removedSourceCount
    default:
        return false
    }
}

private func sumWithoutOverflow(_ values: [Int]) -> Int? {
    var result = 0
    for value in values {
        let (next, overflowed) = result.addingReportingOverflow(value)
        guard !overflowed else { return nil }
        result = next
    }
    return result
}

private func cacheStorageIsEnabled(_ storage: RepositorySyntaxCacheStorage) -> Bool {
    guard let location = storage.location else { return false }
    return !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (location as NSString).isAbsolutePath
        && storage.dataClasses == RepositorySyntaxCacheStore.retainedDataClasses
        && storage.byteCount > 0
        && storage.contentDigest != nil
}

private func cacheStorageIsDisabled(_ storage: RepositorySyntaxCacheStorage) -> Bool {
    storage.location == nil
        && storage.dataClasses.isEmpty
        && storage.byteCount == 0
        && storage.contentDigest == nil
        && !storage.writePerformed
}

private func fullRebuildIsValid(
    storage: RepositorySyntaxCacheStorage,
    selectedSourceCount: Int,
    reusedSourceCount: Int,
    recomputedSourceCount: Int,
    removedSourceCount: Int,
    invalidations: [RepositorySyntaxCacheInvalidation],
    expectedReasons: Set<RepositorySyntaxCacheInvalidationReason>
) -> Bool {
    cacheStorageIsEnabled(storage)
        && storage.writePerformed
        && reusedSourceCount == 0
        && recomputedSourceCount == selectedSourceCount
        && removedSourceCount == 0
        && !invalidations.isEmpty
        && Set(invalidations.map(\.reason)).isSubset(of: expectedReasons)
        && invalidations.allSatisfy { $0.sourceCount == selectedSourceCount }
}
