import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("R2 repository syntax fact cache")
struct RepositorySyntaxCacheTests {
    @Test("Cold, warm, and one-file analyses report exact reuse")
    func coldWarmAndOneFileChange() throws {
        try withTemporaryCache { cache in
            let sources = fixtureSources()
            let cold = try analyze(sources, cache: cache)
            let coldBytes = try Data(contentsOf: cache)

            #expect(cold.cacheReport.disposition == .coldRebuild)
            #expect(cold.cacheReport.recomputedSourceCount == sources.count)
            #expect(cold.cacheReport.reusedSourceCount == 0)
            #expect(
                cold.cacheReport.sourceSnapshotDigest
                    == cold.evidenceReport.snapshot.contentDigest
            )
            #expect(cold.cacheReport.storage.writePerformed)
            #expect(invalidationCount(.cacheMissing, in: cold.cacheReport) == sources.count)

            let warm = try analyze(sources, cache: cache)
            #expect(warm.evidenceReport == cold.evidenceReport)
            #expect(warm.cacheReport.disposition == .warmReuse)
            #expect(warm.cacheReport.reusedSourceCount == sources.count)
            #expect(warm.cacheReport.recomputedSourceCount == 0)
            #expect(!warm.cacheReport.storage.writePerformed)
            #expect(warm.cacheReport.invalidations.isEmpty)
            #expect(try Data(contentsOf: cache) == coldBytes)

            var edited = sources
            edited[1] = SourceUnit(
                path: edited[1].path,
                module: edited[1].module,
                content: edited[1].content + "\n// content-only edit\n"
            )
            let partial = try analyze(edited, cache: cache)
            let uncached = try RepositoryAnalyzer().analyze(edited)
            #expect(partial.evidenceReport == uncached)
            #expect(partial.cacheReport.disposition == .partialRebuild)
            #expect(partial.cacheReport.recomputedSourceCount == 1)
            #expect(partial.cacheReport.reusedSourceCount == sources.count - 1)
            #expect(invalidationCount(.sourceContentChanged, in: partial.cacheReport) == 1)
        }
    }

    @Test("Incoming fact budgets invalidate the exact downstream dependency closure")
    func budgetDependencyInvalidation() throws {
        try withTemporaryCache { cache in
            let configuration = try configuration(maximumAnalysisUnitsPerRule: 1)
            let initial = [
                SourceUnit(path: "A.swift", content: "enum A {}\n"),
                SourceUnit(path: "B.swift", content: "func b(_ value: Int) {}\n"),
                SourceUnit(path: "C.swift", content: "func c(_ value: Int) {}\n"),
            ]
            _ = try analyze(initial, cache: cache, configuration: configuration)
            var edited = initial
            edited[0] = SourceUnit(path: "A.swift", content: "func a(_ value: Int) {}\n")

            let result = try analyze(edited, cache: cache, configuration: configuration)
            #expect(result.cacheReport.recomputedSourceCount == 3)
            #expect(result.cacheReport.reusedSourceCount == 0)
            #expect(invalidationCount(.sourceContentChanged, in: result.cacheReport) == 1)
            #expect(invalidationCount(.dependencyChanged, in: result.cacheReport) == 2)
            let uncached = try RepositoryAnalyzer().analyze(
                edited,
                configuration: configuration
            )
            #expect(result.evidenceReport == uncached)
        }
    }

    @Test("Metadata, additions, and removals report exact invalidation reasons")
    func structuralInvalidationReasons() throws {
        try withTemporaryCache { cache in
            let initial = fixtureSources()
            _ = try analyze(initial, cache: cache)

            var metadataEdited = initial
            metadataEdited[2] = SourceUnit(
                path: metadataEdited[2].path,
                module: "ChangedModule",
                content: metadataEdited[2].content
            )
            let metadata = try analyze(metadataEdited, cache: cache)
            #expect(metadata.cacheReport.reusedSourceCount == 2)
            #expect(metadata.cacheReport.recomputedSourceCount == 1)
            #expect(
                metadata.cacheReport.invalidations == [
                    RepositorySyntaxCacheInvalidation(
                        reason: .sourceMetadataChanged,
                        sourceCount: 1
                    )
                ]
            )

            let addedSources =
                metadataEdited + [
                    SourceUnit(path: "Z.swift", content: "enum Z {}\n")
                ]
            let added = try analyze(addedSources, cache: cache)
            #expect(added.cacheReport.reusedSourceCount == 3)
            #expect(added.cacheReport.recomputedSourceCount == 1)
            #expect(
                added.cacheReport.invalidations == [
                    RepositorySyntaxCacheInvalidation(reason: .sourceAdded, sourceCount: 1)
                ]
            )

            let removed = try analyze(metadataEdited, cache: cache)
            #expect(removed.cacheReport.reusedSourceCount == 3)
            #expect(removed.cacheReport.recomputedSourceCount == 0)
            #expect(removed.cacheReport.removedSourceCount == 1)
            #expect(
                removed.cacheReport.invalidations == [
                    RepositorySyntaxCacheInvalidation(reason: .sourceRemoved, sourceCount: 1)
                ]
            )
        }
    }

    @Test("Forced rebuild replaces compatible state and interrupted siblings are inert")
    func forcedAndInterruptedWriteBehavior() throws {
        try withTemporaryCache { cache in
            let sources = fixtureSources()
            _ = try analyze(sources, cache: cache)
            let interrupted = URL(fileURLWithPath: cache.path + ".interrupted")
            try Data(#"{"partial":true"#.utf8).write(to: interrupted)
            let before = try Data(contentsOf: cache)

            let warm = try analyze(sources, cache: cache)
            #expect(warm.cacheReport.disposition == .warmReuse)
            #expect(try Data(contentsOf: cache) == before)
            #expect(try Data(contentsOf: interrupted) == Data(#"{"partial":true"#.utf8))

            let forced = try RepositoryAnalyzer().analyze(
                sources,
                cachePolicy: .rebuild(cache)
            )
            #expect(forced.cacheReport.disposition == .forcedRebuild)
            #expect(forced.cacheReport.recomputedSourceCount == sources.count)
            #expect(forced.cacheReport.storage.writePerformed)
            #expect(invalidationCount(.forcedRebuild, in: forced.cacheReport) == sources.count)
        }
    }

}
