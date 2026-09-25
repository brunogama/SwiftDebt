import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("R2 repository syntax cache CLI")
struct RepositorySyntaxCacheCLIWorkflowTests {
    @Test("Real CLI recovers and preserves report schemas across cache states")
    func coldWarmEditCorruptInterruptAndRebuild() throws {
        let fixture = try makeCacheFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try initializeGitRepository(fixture.repository)
        let arguments = cacheArguments(fixture)

        let cold = try runSwiftDebt(arguments)
        let coldStandardOutput = Data(cold.stdout.utf8)
        let coldEvidence = try Data(contentsOf: fixture.evidence)
        let coldCache = try Data(contentsOf: fixture.cache)
        let coldActivity = try decodeCacheReport(fixture.activity)
        let schemaTwo = try JSONDecoder().decode(AnalysisReport.self, from: coldStandardOutput)
        let schemaOne = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: coldEvidence)
        let cacheDocument = try JSONDecoder().decode(
            RepositorySyntaxCacheDocument.self,
            from: coldCache
        )
        try cacheDocument.validate()
        let cacheContentDigest = try RepositorySyntaxCacheStore().digest(coldCache)

        #expect(cold.status == 0)
        #expect(cold.stderr.isEmpty)
        #expect(schemaTwo.schemaVersion == 2)
        #expect(schemaOne.schemaVersion == 1)
        #expect(coldActivity.schemaVersion == 1)
        #expect(coldActivity.sourceSnapshotDigest == schemaOne.snapshot.contentDigest)
        #expect(cacheDocument.reportKind == "swiftdebt-repository-syntax-cache-store")
        #expect(cacheDocument.schemaVersion == 1)
        #expect(cacheDocument.sourceSnapshotDigest == schemaOne.snapshot.contentDigest)
        #expect(coldActivity.disposition == .coldRebuild)
        #expect(coldActivity.recomputedSourceCount == 3)
        #expect(coldActivity.storage.byteCount == coldCache.count)
        #expect(coldActivity.storage.contentDigest == cacheContentDigest)
        #expect(coldActivity.storage.dataClasses == RepositorySyntaxCacheStore.retainedDataClasses)
        #expect(try gitStatus(fixture.repository).isEmpty)

        let warm = try runSwiftDebt(arguments)
        let warmActivity = try decodeCacheReport(fixture.activity)
        #expect(warm.status == 0)
        #expect(Data(warm.stdout.utf8) == coldStandardOutput)
        #expect(try Data(contentsOf: fixture.evidence) == coldEvidence)
        #expect(try Data(contentsOf: fixture.cache) == coldCache)
        #expect(warmActivity.disposition == .warmReuse)
        #expect(warmActivity.reusedSourceCount == 3)
        #expect(warmActivity.recomputedSourceCount == 0)
        #expect(!warmActivity.storage.writePerformed)
        #expect(try gitStatus(fixture.repository).isEmpty)

        let editedSource = fixture.repository.appendingPathComponent("Models.swift")
        let original = try String(contentsOf: editedSource, encoding: .utf8)
        try (original + "\n// cache invalidation probe\n").write(
            to: editedSource,
            atomically: true,
            encoding: .utf8
        )
        let edited = try runSwiftDebt(arguments)
        let editedEvidence = try Data(contentsOf: fixture.evidence)
        let editedActivity = try decodeCacheReport(fixture.activity)
        #expect(edited.status == 0)
        #expect(editedActivity.disposition == .partialRebuild)
        #expect(editedActivity.recomputedSourceCount == 1)
        #expect(editedActivity.reusedSourceCount == 2)
        #expect(invalidationCount(.sourceContentChanged, in: editedActivity) == 1)

        let uncachedEvidence = fixture.artifacts.appendingPathComponent("uncached-evidence.json")
        let uncachedActivity = fixture.artifacts.appendingPathComponent("uncached-activity.json")
        let uncached = try runSwiftDebt([
            "analyze", fixture.repository.path, "--format", "json", "--jobs", "1",
            "--repository-evidence", uncachedEvidence.path,
            "--repository-cache-report", uncachedActivity.path,
            "--no-repository-cache",
        ])
        #expect(uncached.status == 0)
        #expect(uncached.stdout == edited.stdout)
        #expect(try Data(contentsOf: uncachedEvidence) == editedEvidence)
        #expect(try decodeCacheReport(uncachedActivity).disposition == .disabled)

        try Data(#"{"partial":"#.utf8).write(to: fixture.cache, options: .atomic)
        let recovered = try runSwiftDebt(arguments)
        let recoveredActivity = try decodeCacheReport(fixture.activity)
        #expect(recovered.status == 0)
        #expect(try Data(contentsOf: fixture.evidence) == editedEvidence)
        #expect(recoveredActivity.disposition == .recoveredCorruption)
        #expect(invalidationCount(.cacheCorrupt, in: recoveredActivity) == 3)

        let interrupted = URL(fileURLWithPath: fixture.cache.path + ".interrupted")
        try Data(#"{"incomplete":true"#.utf8).write(to: interrupted)
        let recoveredCache = try Data(contentsOf: fixture.cache)
        let afterInterruption = try runSwiftDebt(arguments)
        #expect(afterInterruption.status == 0)
        #expect(try decodeCacheReport(fixture.activity).disposition == .warmReuse)
        #expect(try Data(contentsOf: fixture.cache) == recoveredCache)
        #expect(FileManager.default.fileExists(atPath: interrupted.path))

        let forced = try runSwiftDebt(arguments + ["--rebuild-repository-cache"])
        let forcedActivity = try decodeCacheReport(fixture.activity)
        #expect(forced.status == 0)
        #expect(forcedActivity.disposition == .forcedRebuild)
        #expect(forcedActivity.recomputedSourceCount == 3)
        #expect(invalidationCount(.forcedRebuild, in: forcedActivity) == 3)
    }

    @Test("Cache options require repository evidence and cannot collide with outputs")
    func optionAndIdentityGuards() throws {
        let fixture = try makeCacheFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let missingEvidence = try runSwiftDebt([
            "analyze", fixture.repository.path, "--repository-cache", fixture.cache.path,
        ])
        #expect(missingEvidence.status == 2)
        #expect(missingEvidence.stderr.contains("require --repository-evidence"))

        let collision = fixture.artifacts.appendingPathComponent("collision.json")
        let colliding = try runSwiftDebt([
            "analyze", fixture.repository.path,
            "--repository-evidence", collision.path,
            "--repository-cache", collision.path,
        ])
        #expect(colliding.status == 2)
        #expect(colliding.stderr.contains("another output"))
        #expect(!FileManager.default.fileExists(atPath: collision.path))
    }

    private func cacheArguments(_ fixture: CacheCLIFixture) -> [String] {
        [
            "analyze", fixture.repository.path, "--format", "json", "--jobs", "1",
            "--repository-evidence", fixture.evidence.path,
            "--repository-cache", fixture.cache.path,
            "--repository-cache-report", fixture.activity.path,
        ]
    }

    private func decodeCacheReport(_ url: URL) throws -> RepositorySyntaxCacheReport {
        try JSONDecoder().decode(RepositorySyntaxCacheReport.self, from: Data(contentsOf: url))
    }

    private func invalidationCount(
        _ reason: RepositorySyntaxCacheInvalidationReason,
        in report: RepositorySyntaxCacheReport
    ) -> Int {
        report.invalidations.first { $0.reason == reason }?.sourceCount ?? 0
    }
}
