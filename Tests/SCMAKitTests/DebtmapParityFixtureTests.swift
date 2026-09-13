import CryptoKit
import Foundation
import Testing

@Suite("Debtmap parity matrix and fixture harness")
struct DebtmapParityFixtureTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    @Test func parityMatrixRequiresProofForEveryInScopeCapability() throws {
        let matrix: ParityMatrix = try loadJSON("docs/debtmap/parity-matrix.v0.23.0.json")

        #expect(matrix.debtmapVersion == "0.23.0")
        #expect(matrix.matrixSchemaVersion == 1)
        #expect(matrix.statuses == ["implemented", "intentional-divergence", "out-of-scope"])
        #expect(matrix.statuses.allSatisfy { !(matrix.statusDefinition[$0] ?? "").isEmpty })
        #expect(
            matrix.validation.testFilter
                == "DebtmapParityFixtureTests.parityMatrixRequiresProofForEveryInScopeCapability"
        )
        #expect(matrix.capabilities.map(\.id) == matrix.capabilities.map(\.id).sorted())
        #expect(Set(matrix.capabilities.map(\.id)).count == matrix.capabilities.count)

        for capability in matrix.capabilities {
            #expect(matrix.statuses.contains(capability.status), "Unknown status for \(capability.id)")
        }

        for capability in matrix.capabilities where capability.scope == "in-scope" {
            #expect(!capability.proofs.isEmpty, "Missing proof for \(capability.id)")
            for proof in capability.proofs {
                #expect(!proof.reference.isEmpty, "Empty proof reference for \(capability.id)")
            }
        }
    }

    @Test func goldenFixtureOutputsRemainDeterministic() throws {
        let fixture: GoldenFixture = try loadJSON("Tests/SCMAKitTests/Fixtures/DebtmapParity/canonical-workflow.fixture.json")

        #expect(fixture.schemaVersion == 1)
        #expect(fixture.generatedAt == "2026-09-12T00:00:00Z")
        #expect(fixture.gitHistory.referenceTime == "2026-09-12T00:00:00Z")
        #expect(!fixture.gitHistory.commits.isEmpty)
        #expect(fixture.evidenceAvailability.contains { $0.state == "unavailable" })

        let json = try renderJSON(fixture)
        let markdown = renderMarkdown(fixture)
        let dot = renderDOT(fixture)
        let cli = try renderCLI(fixture)

        let repeatedJSON = try renderJSON(fixture)
        let repeatedMarkdown = renderMarkdown(fixture)
        let repeatedDOT = renderDOT(fixture)
        let repeatedCLI = try renderCLI(fixture)

        #expect(json == repeatedJSON)
        #expect(markdown == repeatedMarkdown)
        #expect(dot == repeatedDOT)
        #expect(cli == repeatedCLI)

        let shuffled = fixture.shuffledForDeterminismCheck()
        let shuffledJSON = try renderJSON(shuffled)
        let shuffledCLI = try renderCLI(shuffled)
        let expectedJSON = try read("Tests/SCMAKitTests/Fixtures/DebtmapParity/canonical-report.golden.json")
        let expectedMarkdown = try read("Tests/SCMAKitTests/Fixtures/DebtmapParity/canonical-report.golden.md")
        let expectedDOT = try read("Tests/SCMAKitTests/Fixtures/DebtmapParity/canonical-graph.golden.dot")
        let expectedCLI = try read("Tests/SCMAKitTests/Fixtures/DebtmapParity/canonical-cli-exits.golden.json")

        #expect(json == shuffledJSON)
        #expect(markdown == renderMarkdown(shuffled))
        #expect(dot == renderDOT(shuffled))
        #expect(cli == shuffledCLI)
        #expect(json == expectedJSON)
        #expect(markdown == expectedMarkdown)
        #expect(dot == expectedDOT)
        #expect(cli == expectedCLI)
    }

    @Test func benchmarkMethodologyReferencesFrozenInputs() throws {
        let methodology: BenchmarkMethodology = try loadJSON("benchmarks/debtmap-baseline/methodology.v1.json")

        #expect(methodology.baselineCommit == "b0ae66be2065084b29b8b5da0a86d5cd049feced")
        #expect(methodology.schemaVersion == 1)
        #expect(methodology.outputDirectory == ".scma/benchmarks/debtmap-baseline")
        #expect(
            methodology.measurements == [
                "wall-clock-seconds", "peak-memory-bytes", "phase-wall-clock-nanoseconds",
            ]
        )
        #expect(methodology.methodology.allSatisfy { !$0.isEmpty })
        #expect(methodology.platformVariance.noiseControls.contains("five measured runs"))
        #expect(methodology.platformVariance.requiredMetadata.contains("swift-version"))
        #expect(methodology.warmupRuns == 1)
        #expect(methodology.measuredRuns == 5)
        #expect(!methodology.commands.isEmpty)

        for command in methodology.commands {
            #expect(!command.name.isEmpty)
            #expect(!command.argv.isEmpty)
            #expect(command.argv.allSatisfy { !$0.isEmpty })
        }
        #expect(
            methodology.commands.filter { $0.name.hasPrefix("measure-") }.allSatisfy {
                $0.argv.contains("--profile-output")
            }
        )
        #expect(methodology.performanceGate.comparisonUnit == "Equivalent SwiftSCMA workload only")
        #expect(methodology.performanceGate.disallowedComparisons.contains("Debtmap Rust workload"))
        #expect(methodology.performanceGate.approvedExceptionEvidence.contains("written justification for accepting the regression"))
        #expect(methodology.regressionBudgets.map(\.name) == ["baseline-analysis", "full-evidence-analysis"])
        #expect(methodology.regressionBudgets.allSatisfy { $0.workloadFamily == "SwiftSCMA" })
        #expect(methodology.regressionBudgets.map(\.maximumPeakMemoryRegressionPercent) == [15, 15])
        #expect(methodology.regressionBudgets[0].maximumWallClockRegressionPercent == 10)
        #expect(methodology.regressionBudgets[0].optionalContext == "none")
        #expect(methodology.regressionBudgets[1].maximumWallClockRegressionPercent == 20)
        #expect(methodology.regressionBudgets[1].optionalContext == "coverage-and-repository-history")

        for input in methodology.inputs {
            let url = root.appendingPathComponent(input.path)
            let data = try Data(contentsOf: url)
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(data.count == input.utf8ByteCount, "Byte count drifted for \(input.path)")
            #expect(text.split(separator: "\n", omittingEmptySubsequences: false).count == input.lineCount)
            #expect(sha256Hex(data) == input.sha256, "SHA-256 drifted for \(input.path)")
        }
    }

    private func loadJSON<T: Decodable>(_ path: String) throws -> T {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
