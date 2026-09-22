import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit
@testable import SwiftDebtReporting

@Suite("Ranked debt analysis composition")
struct RankedDebtAnalysisTests {
    @Test func endToEndServiceProducesStableRankedDebtWithProviderEvidence() async throws {
        let root = try temporaryGitTestDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try initializeGitRepository(at: root)
        let source = "Sources/Processor.swift"
        try writeGitFixture(
            """
            final class Processor {
                var cache: [Int] = []
                public func run(_ first: Int, _ second: Int, _ third: Int, _ fourth: Int, _ fifth: Int, _ sixth: Int) async throws {
                    cache.append(first)
                    if first > 0 {
                        for value in cache {
                            if value > second { print(value) }
                        }
                    }
                }
            }
            """,
            name: source,
            root: root
        )
        try commitGitFixture(
            root: root,
            message: "fix: stabilize processor debt fixture",
            authorEmail: "fixture@example.test",
            timestamp: "2026-09-01T00:00:00Z"
        )
        try """
            SF:\(root.appendingPathComponent(source).path)
            FN:3,Workspace.Processor.run(_:_:_:_:_:_:)
            FNDA:0,Workspace.Processor.run(_:_:_:_:_:_:)
            DA:3,0
            DA:4,0
            DA:5,0
            DA:6,0
            DA:7,0
            end_of_record
            """.write(to: root.appendingPathComponent("coverage.lcov"), atomically: true, encoding: .utf8)

        let request = AnalysisRequest(
            path: root.path,
            typeScope: .nominals,
            jobs: 4,
            debtAnalysisOptions: DebtAnalysisOptions(aggregationStrategy: .file, top: 5, problematicItemScoreThreshold: 0),
            lcovPath: "coverage.lcov",
            debtReferenceTime: ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z")
        )
        let first = try await AnalysisService().run(request)
        let second = try await AnalysisService().run(request)
        let analysis = try #require(first.rankedDebtAnalysis)

        #expect(analysis == second.rankedDebtAnalysis)
        #expect(!analysis.items.isEmpty)
        #expect(!analysis.aggregations.isEmpty)
        #expect(analysis.items.allSatisfy { !$0.score.breakdown.contributions.isEmpty })
        #expect(analysis.items.contains { item in
            item.item.evidence.contains { $0.kind.hasPrefix("git-history.") && $0.availability.isAvailable }
        })
        #expect(analysis.items.contains { item in
            item.item.evidence.contains { $0.kind == "coverage.lcov" && $0.availability.isAvailable }
        })
        #expect(analysis.items.contains { item in
            item.item.evidence.contains { $0.kind.hasPrefix("swift.side-effect.") || $0.kind.hasPrefix("swift.api-risk.") }
        })
    }

    @Test func providerUnavailabilityIsRankedAsUnavailableEvidenceNotZero() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "struct Worker { func run() { print(1) } }".write(
            to: root.appendingPathComponent("Sources/Worker.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await AnalysisService().run(.init(
            path: root.path,
            typeScope: .nominals,
            debtAnalysisOptions: DebtAnalysisOptions(aggregationStrategy: .none),
            lcovPath: "missing.lcov",
            debtReferenceTime: ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z")
        ))
        let analysis = try #require(result.rankedDebtAnalysis)
        let unavailable = analysis.items.flatMap { $0.score.breakdown.unavailableEvidence }

        #expect(unavailable.contains { $0.kind == "coverage.lcov" && ($0.reason ?? "").contains("LCOV unavailable") })
        #expect(unavailable.contains { $0.kind.hasPrefix("git-history.") && ($0.reason ?? "").contains("not a git repository") })
        #expect(unavailable.allSatisfy { $0.configuredWeight > 0 })
        #expect(analysis.summary.unavailableEvidenceCount == unavailable.count)
    }

    @Test func aggregateOnlyNoAggregationAndFiltersAreDeterministic() throws {
        let items = [
            debtItem(id: "callable:high", level: .callable, file: "Sources/A.swift", kind: "swift.cognitive-complexity", score: 90),
            debtItem(id: "type:low", level: .type, file: "Sources/A.swift", kind: "git-history.change-frequency", score: 20),
            debtItem(id: "file:filtered", level: .file, file: "Sources/B.swift", kind: "coverage.lcov", score: 10),
        ]

        let noAggregation = DebtAnalysisBuilder(options: DebtAnalysisOptions(
            aggregationStrategy: .none,
            minPriority: .medium,
            categories: ["swift"]
        )).analyze(items: items)
        let aggregateOnly = DebtAnalysisBuilder(options: DebtAnalysisOptions(
            aggregationStrategy: .aggregateOnly,
            problematicItemScoreThreshold: 80
        )).analyze(items: items)
        let tail = DebtAnalysisBuilder(options: DebtAnalysisOptions(
            aggregationStrategy: .file,
            tail: 1
        )).analyze(items: items)

        #expect(noAggregation.aggregations.isEmpty)
        #expect(noAggregation.items.map(\.item.id) == ["callable:high"])
        #expect(aggregateOnly.items.isEmpty)
        #expect(aggregateOnly.aggregations.map(\.memberItemIDs) == [["callable:high"]])
        #expect(tail.items.map(\.item.id) == ["file:filtered"])
    }

    @Test func configurationPresetCanEnableRankedDebtWithoutChangingReportFormat() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "class Configured { func run(_ value: Int) { if value > 0 { print(value) } } }".write(
            to: root.appendingPathComponent("Configured.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
            {
              "format": "json",
              "debtAnalysis": {
                "preset": "strict",
                "aggregationStrategy": "none",
                "top": 1
              }
            }
            """.write(to: root.appendingPathComponent(".swift-debt.json"), atomically: true, encoding: .utf8)

        let result = try await AnalysisService().run(.init(path: root.path))
        let analysis = try #require(result.rankedDebtAnalysis)
        _ = try JSONDecoder().decode(AnalysisReport.self, from: Data(result.standardOutput.utf8))

        #expect(analysis.options.preset == .strict)
        #expect(analysis.aggregations.isEmpty)
        #expect(analysis.items.count <= 1)
    }

    @Test func existingReportPathDoesNotRequireRankedDebtAnalysis() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "class Legacy { func run() {} }".write(
            to: root.appendingPathComponent("Legacy.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await AnalysisService().run(.init(path: root.path, format: .json))
        let decoded = try JSONDecoder().decode(AnalysisReport.self, from: Data(result.standardOutput.utf8))
        let text = try ReportRenderer().render(decoded, format: .text, root: root.path)

        #expect(result.rankedDebtAnalysis == nil)
        #expect(decoded.complete)
        #expect(text.contains("SwiftDebt"))
    }

    private func debtItem(
        id: String,
        level: DebtAggregationLevel,
        file: String,
        kind: String,
        score: Double
    ) -> DebtItem {
        let location = DebtLocation(module: "Workspace", file: file, line: 1, column: 1)
        return DebtItem(
            id: id,
            entity: DebtEntity(id: id, displayName: id, level: level, location: location),
            evidence: [
                DebtEvidence(
                    id: "\(id):evidence",
                    kind: kind,
                    weight: 1,
                    normalizedScore: score,
                    rawValue: "score=\(score)",
                    location: location,
                    note: "test evidence"
                )
            ]
        )
    }
}
