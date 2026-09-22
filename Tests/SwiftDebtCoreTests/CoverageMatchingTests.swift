import Foundation
import Testing

@testable import SwiftDebtCore

@Suite("LCOV coverage matching and scoring")
struct CoverageMatchingTests {
    @Test func fixturesCoverPathFunctionAndAvailabilityCases() throws {
        let report = LcovParser().parse(try fixture("canonical.lcov"))
        let result = CoverageMatcher().match(report: report, entities: canonicalEntities(), repositoryRoot: "/repo")

        #expect(report.records.map(\.sourcePath) == [
            ".build/generated/Generated.swift",
            "/repo/Sources/App/Processor.swift",
            "Sources/App/Extensions.swift",
            "Sources/App/Unused.swift",
        ])
        #expect(result.evidence.first { $0.id == "callable:App.Processor.process(value:):coverage:lcov" }?.availability.state == .measuredCoverage)
        #expect(result.evidence.first { $0.id == "callable:App.Processor.process(value:):coverage:lcov" }?.normalizedScore == 100)
        #expect(result.evidence.first { $0.id == "callable:App.Processor.process(text:):coverage:lcov" }?.availability.state == .zeroCoverage)
        #expect(result.evidence.first { $0.id == "callable:App.Processor.process(text:):coverage:lcov" }?.normalizedScore == 0)
        #expect(result.evidence.first { $0.id == "callable:App.Processor.extended():coverage:lcov" }?.availability.state == .measuredCoverage)
        #expect(result.evidence.first { $0.id == "callable:App.Processor.missing():coverage:lcov" }?.availability.state == .missingFile)
        #expect(result.evidence.first { $0.id == "callable:App.Processor.unknown():coverage:lcov" }?.availability.state == .unmatchedEntity)
        #expect(result.diagnostics.contains { $0.sourcePath == ".build/generated/Generated.swift" && $0.entityID == nil })
        #expect(result.diagnostics.contains { $0.sourcePath == "Sources/App/Unused.swift" && $0.entityID == nil })
    }

    @Test func diagnosticOutputExplainsAttemptedMatchingStrategies() throws {
        let report = LcovParser().parse(try fixture("canonical.lcov"))
        let result = CoverageMatcher().match(report: report, entities: canonicalEntities(), repositoryRoot: "/repo")
        let output = CoverageMatcher().renderDiagnostics(result.diagnostics)

        #expect(output.contains("App.Processor.process(value:): measuredCoverage"))
        #expect(output.contains("strategies=sourcePathExact>functionNameExact"))
        #expect(output.contains("App.Processor.extended(): measuredCoverage"))
        #expect(output.contains("strategies=sourcePathExact>functionNameExact>functionNameSuffix"))
        #expect(output.contains("App.Processor.unknown(): unmatchedEntity"))
        #expect(output.contains("functionStartLine>executableLine"))
        #expect(output.contains(".build/generated/Generated.swift: unmatchedEntity"))
    }

    @Test(arguments: [
        "App.Processor.process() -> ()",
        "$s3App9ProcessorC7processyyF",
    ])
    func functionStartLineMatchesWhenCoverageNameDiffersFromSwiftEntity(coverageName: String) throws {
        let report = LcovReport(records: [
            LcovRecord(
                sourcePath: "Sources/App/Processor.swift",
                functions: [LcovFunctionDefinition(line: 42, name: coverageName)],
                functionHits: [LcovFunctionHit(name: coverageName, hits: 3)]
            )
        ])
        let subject = entity(
            "callable:App.Processor.process()",
            "App.Processor.process()",
            file: "Sources/App/Processor.swift",
            line: 42
        )

        let result = CoverageMatcher().match(report: report, entities: [subject])
        let evidence = try #require(result.evidence.first)
        let diagnostic = try #require(result.diagnostics.first)

        #expect(evidence.availability.state == .measuredCoverage)
        #expect(evidence.normalizedScore == 100)
        #expect(diagnostic.matchedFunction == coverageName)
        #expect(diagnostic.attemptedStrategies == [
            .sourcePathExact, .functionNameExact, .functionNameSuffix, .functionStartLine,
        ])
    }

    @Test func functionStartLinePreservesZeroCoverage() throws {
        let result = CoverageMatcher().match(
            report: LcovReport(records: [
                LcovRecord(
                    sourcePath: "Sources/App/Processor.swift",
                    functions: [LcovFunctionDefinition(line: 42, name: "lcov-only-name")],
                    functionHits: [LcovFunctionHit(name: "lcov-only-name", hits: 0)]
                )
            ]),
            entities: [entity(
                "callable:App.Processor.process()", "App.Processor.process()",
                file: "Sources/App/Processor.swift", line: 42
            )]
        )

        #expect(result.evidence.first?.availability.state == .zeroCoverage)
        #expect(result.evidence.first?.normalizedScore == 0)
        #expect(result.diagnostics.first?.matchedFunction == "lcov-only-name")
    }

    @Test func functionStartLineRejectsAmbiguousOrHitlessDefinitions() {
        let subject = entity(
            "callable:App.Processor.process()", "App.Processor.process()",
            file: "Sources/App/Processor.swift", line: 42
        )
        let ambiguous = CoverageMatcher().match(
            report: LcovReport(records: [
                LcovRecord(
                    sourcePath: "Sources/App/Processor.swift",
                    functions: [
                        LcovFunctionDefinition(line: 42, name: "first"),
                        LcovFunctionDefinition(line: 42, name: "second"),
                    ],
                    functionHits: [
                        LcovFunctionHit(name: "first", hits: 1),
                        LcovFunctionHit(name: "second", hits: 1),
                    ]
                )
            ]),
            entities: [subject]
        )
        let missingHit = CoverageMatcher().match(
            report: LcovReport(records: [
                LcovRecord(
                    sourcePath: "Sources/App/Processor.swift",
                    functions: [LcovFunctionDefinition(line: 42, name: "definition-only")]
                )
            ]),
            entities: [subject]
        )

        #expect(ambiguous.evidence.first?.availability.state == .unmatchedEntity)
        #expect(ambiguous.diagnostics.first?.matchedFunction == nil)
        #expect(missingHit.evidence.first?.availability.state == .unmatchedEntity)
        #expect(missingHit.diagnostics.first?.matchedFunction == nil)
    }

    @Test func coverageDampenerCannotIncreaseScore() throws {
        let baseEvidence = [
            DebtEvidence(
                id: "complexity",
                kind: "metric",
                weight: 1,
                normalizedScore: 40,
                rawValue: "ccf=8"
            )
        ]
        let fullCoverage = DebtEvidence(
            id: "coverage-full",
            kind: "coverage.lcov",
            weight: 1,
            normalizedScore: 100,
            rawValue: "covered=1/1"
        )
        let partialCoverage = DebtEvidence(
            id: "coverage-partial",
            kind: "coverage.lcov",
            weight: 1,
            normalizedScore: 25,
            rawValue: "covered=1/4"
        )
        let missingCoverage = DebtEvidence(
            id: "coverage-missing",
            kind: "coverage.lcov",
            availability: .unavailable(reason: "no LCOV"),
            weight: 1,
            normalizedScore: nil,
            rawValue: "missing"
        )

        let base = try #require(DebtScoring().score(evidence: baseEvidence).value)
        let withFullCoverage = try #require(DebtScoring().score(evidence: baseEvidence + [fullCoverage]).value)
        let withPartialCoverage = try #require(DebtScoring().score(evidence: baseEvidence + [partialCoverage]).value)
        let withMissingCoverage = try #require(DebtScoring().score(evidence: baseEvidence + [missingCoverage]).value)

        #expect(withFullCoverage == base)
        #expect(withPartialCoverage < base)
        #expect(withMissingCoverage == base)
        #expect(DebtScoring().score(evidence: baseEvidence + [partialCoverage]).breakdown.contributions.last?.contribution ?? 1 <= 0)
    }

    private func canonicalEntities() -> [DebtEntity] {
        [
            entity("callable:App.Processor.process(value:)", "App.Processor.process(value:)", file: "Sources/App/Processor.swift", line: 3),
            entity("callable:App.Processor.process(text:)", "App.Processor.process(text:)", file: "Sources/App/Processor.swift", line: 7),
            entity("callable:App.Processor.extended()", "App.Processor.extended()", file: "Sources/App/Extensions.swift", line: 5),
            entity("callable:App.Processor.unknown()", "App.Processor.unknown()", file: "Sources/App/Processor.swift", line: 99),
            entity("callable:App.Processor.missing()", "App.Processor.missing()", file: "Sources/App/Missing.swift", line: 1),
        ]
    }

    private func entity(_ id: String, _ displayName: String, file: String, line: Int) -> DebtEntity {
        DebtEntity(
            id: id,
            displayName: displayName,
            level: .callable,
            location: DebtLocation(module: "App", file: file, line: line)
        )
    }

    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CoverageMatching")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
