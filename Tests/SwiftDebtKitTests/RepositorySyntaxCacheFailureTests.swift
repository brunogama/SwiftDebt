import Foundation
import Testing

@testable import SwiftDebtKit

extension RepositorySyntaxCacheTests {
    @Test("Invalid cache storage fails instead of falling back to retained state")
    func invalidStorageFailsClosed() throws {
        try withTemporaryCache { cache in
            try FileManager.default.createDirectory(
                at: cache,
                withIntermediateDirectories: true
            )

            #expect(
                throws: RepositorySyntaxCacheFailure.invalidStoragePath(cache.path)
            ) {
                try analyze(fixtureSources(), cache: cache)
            }
        }
    }

    @Test("Library cache policy rejects non-file URLs before storage access")
    func nonFileStorageIsRejected() throws {
        for value in [
            "https://example.invalid/facts.json",
            "file://example.invalid/facts.json",
        ] {
            let remote = try #require(URL(string: value))

            #expect(
                throws: RepositorySyntaxCacheFailure.nonFileStorageURL
            ) {
                try analyze(fixtureSources(), cache: remote)
            }
        }
    }

    @Test("Decoded activity reports reject inconsistent reuse claims")
    func forgedActivityReportIsRejected() throws {
        try withTemporaryCache { cache in
            let report = try analyze(fixtureSources(), cache: cache).cacheReport
            var object = try #require(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
                    as? [String: Any]
            )
            object["reusedSourceCount"] = report.selectedSourceCount
            let forged = try JSONSerialization.data(withJSONObject: object)

            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(RepositorySyntaxCacheReport.self, from: forged)
            }
        }
    }
}
