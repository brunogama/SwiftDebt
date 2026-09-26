import Foundation
import SwiftDebtCore

@testable import SwiftDebtKit

extension RepositorySyntaxCacheTests {
    func analyze(
        _ sources: [SourceUnit],
        cache: URL,
        configuration: RepositoryAnalysisConfiguration = .standard
    ) throws -> RepositoryAnalysisResult {
        try RepositoryAnalyzer().analyze(
            sources,
            configuration: configuration,
            cachePolicy: .reuse(cache)
        )
    }

    func fixtureSources() -> [SourceUnit] {
        [
            SourceUnit(path: "A.swift", content: "func a(_ id: Int, _ name: String, _ flag: Bool) {}\n"),
            SourceUnit(path: "B.swift", content: "func b(_ id: Int, _ name: String, _ flag: Bool) {}\n"),
            SourceUnit(path: "C.swift", content: "func c(_ id: Int, _ name: String, _ flag: Bool) {}\n"),
        ]
    }

    func configuration(maximumAnalysisUnitsPerRule: Int) throws -> RepositoryAnalysisConfiguration {
        try RepositoryAnalysisConfiguration(
            minimumDataClumpElements: 3,
            minimumDataClumpOccurrences: 2,
            minimumRepeatedSwitchOccurrences: 2,
            maximumSourceFiles: 100,
            maximumTotalSourceBytes: 1_000_000,
            maximumAnalysisUnitsPerRule: maximumAnalysisUnitsPerRule,
            maximumDataClumpComparisons: 10_000,
            maximumDetectionsPerRule: 1_000
        )
    }

    func invalidationCount(
        _ reason: RepositorySyntaxCacheInvalidationReason,
        in report: RepositorySyntaxCacheReport
    ) -> Int {
        report.invalidations.first { $0.reason == reason }?.sourceCount ?? 0
    }

    func withTemporaryCache(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swiftdebt-syntax-cache-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("facts.json"))
    }
}
