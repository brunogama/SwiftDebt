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
        #expect(matrix.statuses == ["implemented", "intentional-divergence", "out-of-scope"])
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

        #expect(!fixture.gitHistory.referenceTime.isEmpty)
        #expect(!fixture.gitHistory.commits.isEmpty)
        #expect(fixture.evidenceAvailability.contains { $0.state == "unavailable" })

        let json = try renderJSON(fixture)
        let markdown = renderMarkdown(fixture)
        let dot = renderDOT(fixture)
        let cli = try renderCLI(fixture)

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
        #expect(methodology.measurements == ["wall-clock-seconds", "peak-memory-bytes"])
        #expect(methodology.warmupRuns > 0)
        #expect(methodology.measuredRuns > 0)
        #expect(!methodology.commands.isEmpty)

        for command in methodology.commands {
            #expect(!command.name.isEmpty)
            #expect(!command.argv.isEmpty)
            #expect(command.argv.allSatisfy { !$0.isEmpty })
        }

        for input in methodology.inputs {
            let url = root.appendingPathComponent(input.path)
            let data = try Data(contentsOf: url)
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(data.count == input.utf8ByteCount, "Byte count drifted for \(input.path)")
            #expect(text.split(separator: "\n", omittingEmptySubsequences: false).count == input.lineCount)
        }
    }

    private func loadJSON<T: Decodable>(_ path: String) throws -> T {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
