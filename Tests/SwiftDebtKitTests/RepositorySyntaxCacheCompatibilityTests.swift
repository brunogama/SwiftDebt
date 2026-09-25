import Foundation
import Testing

@testable import SwiftDebtKit

extension RepositorySyntaxCacheTests {
    @Test("Every fact compatibility dimension independently invalidates retained state")
    func compatibilityDimensionsInvalidate() throws {
        for mutation in CompatibilityMutation.allCases {
            try withTemporaryCache { cache in
                let sources = fixtureSources()
                let baseline = try analyze(sources, cache: cache).evidenceReport
                try mutateCompatibility(mutation, in: cache)

                let rebuilt = try analyze(sources, cache: cache)
                let decodedReport = try JSONDecoder().decode(
                    RepositorySyntaxCacheReport.self,
                    from: JSONEncoder().encode(rebuilt.cacheReport)
                )

                #expect(rebuilt.evidenceReport == baseline)
                #expect(decodedReport == rebuilt.cacheReport)
                #expect(rebuilt.cacheReport.disposition == .incompatibleRebuild)
                #expect(invalidationCount(mutation.reason, in: rebuilt.cacheReport) == sources.count)
            }
        }
    }

    private func mutateCompatibility(
        _ mutation: CompatibilityMutation,
        in cache: URL
    ) throws {
        var object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as? [String: Any]
        )
        var compatibility = try #require(object["compatibility"] as? [String: Any])
        switch mutation {
        case .factSchema:
            compatibility["factSchemaVersion"] = 999
        case .projection:
            compatibility["projectionRevision"] = "changed-projection"
        case .provider:
            var provider = try #require(compatibility["provider"] as? [String: Any])
            provider["sourceRevision"] = "changed-provider-revision"
            compatibility["provider"] = provider
        case .ruleSemantics:
            var rules = try #require(compatibility["rules"] as? [[String: Any]])
            rules[0]["semanticRevision"] = 999
            compatibility["rules"] = rules
        }
        object["compatibility"] = compatibility
        let mutated = try JSONSerialization.data(withJSONObject: object)
        let mutatedDocument = try JSONDecoder().decode(
            RepositorySyntaxCacheDocument.self,
            from: mutated
        )
        let integrityUpdatedDocument = try RepositorySyntaxCacheDocument(
            sourceSnapshotDigest: mutatedDocument.sourceSnapshotDigest,
            compatibility: mutatedDocument.compatibility,
            entries: mutatedDocument.entries
        )
        try RepositorySyntaxCacheStore().encoded(integrityUpdatedDocument).write(
            to: cache,
            options: .atomic
        )
    }
}

private enum CompatibilityMutation: CaseIterable {
    case factSchema
    case projection
    case provider
    case ruleSemantics

    var reason: RepositorySyntaxCacheInvalidationReason {
        switch self {
        case .factSchema: .factSchemaMismatch
        case .projection: .projectionChanged
        case .provider: .providerChanged
        case .ruleSemantics: .ruleSemanticsChanged
        }
    }
}
