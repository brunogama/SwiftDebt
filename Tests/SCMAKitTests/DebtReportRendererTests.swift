import Foundation
import SCMACore
import SCMAKit
import Testing

@testable import SCMAReporting

@Suite("Debt report rendering")
struct DebtReportRendererTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func nativeDebtOutputsMatchGoldenFixturesAndExposeSchemaVersion() throws {
        let fixture = makeFixture()
        let renderer = ReportRenderer()

        let json = try renderer.renderDebt(fixture.analysis, format: .debtJSON, graph: fixture.graph)
        let markdown = try renderer.renderDebt(fixture.analysis, format: .debtMarkdown, graph: fixture.graph)
        let dot = try renderer.renderDebt(fixture.analysis, format: .debtDot, graph: fixture.graph)
        let plain = try renderer.renderDebt(fixture.analysis, format: .debtText, graph: fixture.graph)
        let compact = try renderer.renderDebt(fixture.analysis, format: .debtCompact, graph: fixture.graph)
        let debtmap = try renderer.renderDebt(fixture.analysis, format: .debtmapJSON, graph: fixture.graph)

        let decoded = try JSONDecoder().decode(DebtReport.self, from: Data(json.utf8))
        let projection = try JSONDecoder().decode(DebtmapCompatibilityProjection.self, from: Data(debtmap.utf8))

        #expect(decoded.schemaVersion == DebtReportSchema.currentVersion)
        #expect(decoded.reportKind == "swiftscma-debt-report")
        #expect(decoded.missingEvidence.map(\.evidenceID) == ["callable:Beta.run:coverage"])
        #expect(decoded.items.map(\.id) == ["callable:Beta.run", "callable:Alpha.help"])
        let dependencyGraph = try #require(decoded.dependencyGraph)
        #expect(dependencyGraph.nodes.map(\.id) == ["App.Alpha.help()", "App.Beta.run()"])
        #expect(dependencyGraph.edges.count == 1)
        #expect(dependencyGraph.edges[0].source == "App.Beta.run()")
        #expect(dependencyGraph.edges[0].target == "App.Alpha.help()")
        #expect(projection.schemaVersion == 1)
        #expect(projection.projection == "debtmap-compatibility")
        #expect(projection.projectionNote.contains("projection"))
        #expect(projection.projectionNote.contains("not the native SwiftSCMA debt model"))

        let expectedJSON = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json")
        let expectedMarkdown = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-report.golden.md")
        let expectedDOT = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-graph.golden.dot")
        let expectedPlain = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-plain.golden.txt")
        let expectedCompact = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-compact.golden.txt")
        let expectedDebtmap = try read(
            "Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debtmap-projection.golden.json")
        #expect(json == expectedJSON)
        #expect(markdown == expectedMarkdown)
        #expect(dot == expectedDOT)
        #expect(plain == expectedPlain)
        #expect(compact == expectedCompact)
        #expect(debtmap == expectedDebtmap)
    }

    @Test func shuffledAnalysisStillRendersInStableOrder() throws {
        let fixture = makeFixture(shuffled: true)
        let renderer = ReportRenderer()

        let json = try renderer.renderDebt(fixture.analysis, format: .debtJSON, graph: fixture.graph)
        let markdown = try renderer.renderDebt(fixture.analysis, format: .debtMarkdown, graph: fixture.graph)
        let dot = try renderer.renderDebt(fixture.analysis, format: .debtDot, graph: fixture.graph)
        let plain = try renderer.renderDebt(fixture.analysis, format: .debtText, graph: fixture.graph)
        let compact = try renderer.renderDebt(fixture.analysis, format: .debtCompact, graph: fixture.graph)
        let debtmap = try renderer.renderDebt(fixture.analysis, format: .debtmapJSON, graph: fixture.graph)

        let expectedJSON = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-report.golden.json")
        let expectedMarkdown = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-report.golden.md")
        let expectedDOT = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-graph.golden.dot")
        let expectedPlain = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-plain.golden.txt")
        let expectedCompact = try read("Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debt-compact.golden.txt")
        let expectedDebtmap = try read(
            "Tests/SCMAKitTests/Fixtures/DebtReport/canonical-debtmap-projection.golden.json")
        #expect(json == expectedJSON)
        #expect(markdown == expectedMarkdown)
        #expect(dot == expectedDOT)
        #expect(plain == expectedPlain)
        #expect(compact == expectedCompact)
        #expect(debtmap == expectedDebtmap)
    }

    @Test func analysisServiceRendersDebtJSONWhenDebtFormatIsSelected() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "final class Worker { func run(_ value: Int) { if value > 0 { print(value) } } }".write(
            to: directory.appendingPathComponent("Worker.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try await AnalysisService().run(
            .init(
                path: directory.path,
                format: .debtJSON,
                debtAnalysisOptions: DebtAnalysisOptions(aggregationStrategy: .none, top: 1),
                lcovPath: "missing.lcov"
            ))
        let decoded = try JSONDecoder().decode(DebtReport.self, from: Data(result.standardOutput.utf8))

        #expect(decoded.schemaVersion == DebtReportSchema.currentVersion)
        #expect(decoded.reportKind == "swiftscma-debt-report")
        #expect(decoded.items.count <= 1)
        #expect(!decoded.missingEvidence.isEmpty)
        #expect(decoded.dependencyGraph != nil)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func makeFixture(shuffled: Bool = false) -> (analysis: RankedDebtAnalysis, graph: SwiftDependencyGraph) {
        let alphaLocation = DebtLocation(module: "App", file: "Sources/Alpha.swift", line: 3, column: 1)
        let betaLocation = DebtLocation(module: "App", file: "Sources/Beta.swift", line: 12, column: 5)
        let alpha = rankedItem(
            id: "callable:Alpha.help",
            name: "App.Alpha.help()",
            location: alphaLocation,
            value: 72.5,
            priority: .high,
            explanation: "High fan-in concentrates change risk.",
            recommendation: "Reduce fan-in before adding features.",
            evidence: [
                contribution(
                    id: "callable:Alpha.help:coupling",
                    kind: "graph.coupling",
                    score: 72.5,
                    raw: "fanIn=8",
                    location: alphaLocation
                )
            ]
        )
        let beta = rankedItem(
            id: "callable:Beta.run",
            name: "App.Beta.run()",
            location: betaLocation,
            value: 91.25,
            priority: .critical,
            explanation: "Nested async work combines complexity and missing coverage.",
            recommendation: "Extract smaller operations and add coverage.",
            evidence: [
                unavailable(
                    id: "callable:Beta.run:coverage",
                    kind: "coverage.lcov",
                    reason: "LCOV file missing",
                    location: betaLocation
                ),
                contribution(
                    id: "callable:Beta.run:complexity",
                    kind: "swift.cognitive-complexity",
                    score: 91.25,
                    raw: "cognitive=18",
                    location: betaLocation
                ),
            ]
        )
        let items = shuffled ? [alpha, beta] : [beta, alpha]
        let aggregation = DebtAggregation(
            id: "file:Sources",
            level: .file,
            displayName: "Sources",
            location: DebtLocation(module: "App", file: "Sources", line: nil, column: nil),
            memberItemIDs: shuffled
                ? ["callable:Alpha.help", "callable:Beta.run"] : ["callable:Beta.run", "callable:Alpha.help"],
            score: DebtScore(
                value: 81.875,
                priority: .high,
                breakdown: DebtScoreBreakdown(
                    totalConfiguredWeight: 2, totalAvailableWeight: 2, contributions: [], unavailableEvidence: [])
            )
        )
        let analysis = RankedDebtAnalysis(
            options: DebtAnalysisOptions(aggregationStrategy: .file, top: 10, problematicItemScoreThreshold: 50),
            items: items,
            aggregations: [aggregation],
            compactItems: items.map {
                CompactDebtItem(
                    id: $0.item.id,
                    displayName: $0.item.entity.displayName,
                    level: $0.item.entity.level,
                    score: $0.score.value,
                    priority: $0.score.priority,
                    location: $0.item.entity.location
                )
            },
            summary: DebtAnalysisSummary(
                totalItemCount: 2,
                rankedItemCount: 2,
                aggregationCount: 1,
                unavailableEvidenceCount: 1,
                priorityCounts: ["critical": 1, "high": 1]
            )
        )
        let graphNodes = [
            SwiftGraphNode(
                id: "App.Beta.run()",
                kind: .callable,
                module: "App",
                displayName: "Beta.run()",
                location: SourceLocation(file: "Sources/Beta.swift", line: 12, column: 5)
            ),
            SwiftGraphNode(
                id: "App.Alpha.help()",
                kind: .callable,
                module: "App",
                displayName: "Alpha.help()",
                location: SourceLocation(file: "Sources/Alpha.swift", line: 3, column: 1)
            ),
        ]
        let graph = SwiftDependencyGraph(
            nodes: shuffled ? Array(graphNodes.reversed()) : graphNodes,
            edges: [
                SwiftGraphEdge(
                    source: "App.Beta.run()",
                    target: "App.Alpha.help()",
                    kind: .call,
                    confidence: .resolvedSyntax,
                    location: SourceLocation(file: "Sources/Beta.swift", line: 12, column: 15),
                    note: "Beta.run calls Alpha.help"
                )
            ],
            couplingRisks: [],
            dependencyContexts: [],
            statistics: CallGraphStatistics(
                nodeCount: 2,
                edgeCount: 1,
                resolvedEdgeCount: 1,
                ambiguousEdgeCount: 0,
                unresolvedEdgeCount: 0,
                syntaxOnlyNote: "Syntax-only graph."
            ),
            dot: ""
        )
        return (analysis, graph)
    }

    private func rankedItem(
        id: String,
        name: String,
        location: DebtLocation,
        value: Double,
        priority: Priority,
        explanation: String,
        recommendation: String,
        evidence: [DebtEvidence]
    ) -> RankedDebtItem {
        RankedDebtItem(
            item: DebtItem(
                id: id,
                entity: DebtEntity(id: id, displayName: name, level: .callable, location: location),
                evidence: evidence
            ),
            score: DebtScore(
                value: value,
                priority: priority,
                breakdown: DebtScoreBreakdown(
                    totalConfiguredWeight: evidence.reduce(0) { $0 + $1.weight },
                    totalAvailableWeight: evidence.filter(\.availability.isAvailable).reduce(0) { $0 + $1.weight },
                    contributions: evidence.compactMap { item in
                        guard let normalizedScore = item.normalizedScore else { return nil }
                        return DebtScoreContribution(
                            evidenceID: item.id,
                            kind: item.kind,
                            rawValue: item.rawValue,
                            normalizedScore: normalizedScore,
                            configuredWeight: item.weight,
                            effectiveWeight: item.weight,
                            contribution: normalizedScore * item.weight,
                            note: item.note
                        )
                    },
                    unavailableEvidence: evidence.filter { !$0.availability.isAvailable }.map { item in
                        DebtUnavailableEvidence(
                            evidenceID: item.id,
                            kind: item.kind,
                            requirement: item.requirement,
                            configuredWeight: item.weight,
                            reason: item.availability.reason
                        )
                    }
                )
            ),
            category: "swift",
            explanation: explanation,
            recommendation: recommendation
        )
    }

    private func contribution(
        id: String,
        kind: String,
        score: Double,
        raw: String,
        location: DebtLocation
    ) -> DebtEvidence {
        DebtEvidence(
            id: id,
            kind: kind,
            availability: .available,
            weight: 2,
            normalizedScore: score,
            rawValue: raw,
            location: location,
            note: "measured"
        )
    }

    private func unavailable(id: String, kind: String, reason: String, location: DebtLocation) -> DebtEvidence {
        DebtEvidence(
            id: id,
            kind: kind,
            requirement: .required,
            availability: .unavailable(reason: reason),
            weight: 1,
            normalizedScore: nil,
            rawValue: "unavailable",
            location: location,
            note: "No zero-valued risk was fabricated."
        )
    }
}
