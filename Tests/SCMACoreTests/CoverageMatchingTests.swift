import Foundation
import Testing

@testable import SCMACore

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
