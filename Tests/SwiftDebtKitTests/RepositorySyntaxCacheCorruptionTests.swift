import Foundation
import Testing

@testable import SwiftDebtKit

extension RepositorySyntaxCacheTests {
    @Test("Partial, corrupt, and unknown-schema files rebuild without stale fallback")
    func corruptionRecovery() throws {
        try withTemporaryCache { cache in
            let sources = fixtureSources()
            let baseline = try analyze(sources, cache: cache).evidenceReport

            try Data(#"{"entries":"#.utf8).write(to: cache, options: .atomic)
            let partial = try analyze(sources, cache: cache)
            #expect(partial.evidenceReport == baseline)
            #expect(partial.cacheReport.disposition == .recoveredCorruption)
            #expect(invalidationCount(.cacheCorrupt, in: partial.cacheReport) == sources.count)

            var corruptedObject = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any]
            )
            var corruptedDigest = try #require(
                corruptedObject["sourceSnapshotDigest"] as? [String: Any]
            )
            corruptedDigest["value"] = String(repeating: "0", count: 64)
            corruptedObject["sourceSnapshotDigest"] = corruptedDigest
            let corruptedData = try JSONSerialization.data(withJSONObject: corruptedObject)
            let corruptedDocument = try JSONDecoder().decode(
                RepositorySyntaxCacheDocument.self,
                from: corruptedData
            )
            try RepositorySyntaxCacheStore().encoded(corruptedDocument).write(
                to: cache,
                options: .atomic
            )
            let integrity = try analyze(sources, cache: cache)
            #expect(integrity.evidenceReport == baseline)
            #expect(integrity.cacheReport.disposition == .recoveredCorruption)
            #expect(invalidationCount(.cacheCorrupt, in: integrity.cacheReport) == sources.count)

            var object = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any]
            )
            object["schemaVersion"] = 999
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                .write(to: cache, options: .atomic)
            let schema = try analyze(sources, cache: cache)
            #expect(schema.evidenceReport == baseline)
            #expect(schema.cacheReport.disposition == .incompatibleRebuild)
            #expect(invalidationCount(.schemaMismatch, in: schema.cacheReport) == sources.count)

            let changedConfiguration = try configuration(maximumAnalysisUnitsPerRule: 2)
            let incompatible = try analyze(
                sources,
                cache: cache,
                configuration: changedConfiguration
            )
            #expect(incompatible.cacheReport.disposition == .incompatibleRebuild)
            #expect(invalidationCount(.configurationChanged, in: incompatible.cacheReport) == sources.count)
            let uncached = try RepositoryAnalyzer().analyze(
                sources,
                configuration: changedConfiguration
            )
            #expect(incompatible.evidenceReport == uncached)
        }
    }
}
