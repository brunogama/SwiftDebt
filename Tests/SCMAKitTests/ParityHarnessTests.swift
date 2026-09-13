import Foundation
import Testing

@Suite("Debtmap parity acceptance backbone")
struct ParityHarnessTests {
    @Test func parityMatrixRequiresProofForInScopeCapabilities() throws {
        let root = Self.repositoryRoot()
        let matrix = try Self.parityMatrix(root: root)

        try Self.validate(matrix, repositoryRoot: root)

        var invalid = matrix
        let index = try #require(invalid.capabilities.firstIndex { $0.status != CapabilityStatus.outOfScope })
        invalid.capabilities[index].proof = []

        #expect(throws: ParityValidationError.self) {
            try Self.validate(invalid, repositoryRoot: root)
        }
    }

    @Test func goldenOutputsAreStableAcrossRepeatedRuns() throws {
        let root = Self.repositoryRoot()
        let first = GoldenFixture.unordered()
        let second = GoldenFixture.reversed()
        let cases: [(name: String, render: (GoldenFixture) -> String)] = [
            ("report.json.golden", GoldenFixtureRenderer.json),
            ("report.md.golden", GoldenFixtureRenderer.markdown),
            ("digraph.dot.golden", GoldenFixtureRenderer.dot),
            ("cli-exit.golden", GoldenFixtureRenderer.cliExit),
        ]

        for item in cases {
            let firstOutput = item.render(first)
            let secondOutput = item.render(second)
            let golden = try Self.fixture(root: root, name: item.name)

            #expect(firstOutput == secondOutput)
            #expect(firstOutput == golden)
        }
    }

    @Test func baselineBenchmarkManifestFreezesInputsAndMethodology() throws {
        let root = Self.repositoryRoot()
        let manifestURL = root.appendingPathComponent("Benchmarks/SwiftSCMABaseline/manifest.json")
        let manifest = try JSONDecoder().decode(BenchmarkManifest.self, from: Data(contentsOf: manifestURL))

        #expect(manifest.schemaVersion == 1)
        #expect(manifest.configuration.jobs == 1)
        #expect(manifest.configuration.typeScope == "nominals")
        #expect(manifest.metrics == ["wall-clock-seconds", "peak-rss-bytes"])
        #expect(manifest.runs.warmup == 1)
        #expect(manifest.runs.measured == 5)
        #expect(manifest.runs.reportedStatistic == "median")
        #expect(manifest.measurementCommands.contains("swift build -c release --product scma"))
        #expect(manifest.measurementCommands.contains { $0.contains("/usr/bin/time -l") })
        #expect(manifest.measurementCommands.contains { $0.contains("/usr/bin/time -v") })

        let input = try #require(manifest.inputs.first)
        let inputURL = root.appendingPathComponent(input.path)
        let inputData = try Data(contentsOf: inputURL)
        let inputText = String(decoding: inputData, as: UTF8.self)

        #expect(input.module == "SwiftSCMABaseline")
        #expect(inputData.count == input.utf8ByteCount)
        #expect(inputText.filter { $0 == "\n" }.count == input.lineCount)
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func parityMatrix(root: URL) throws -> ParityMatrix {
        let url = root.appendingPathComponent("docs/debtmap-parity-matrix.json")
        return try JSONDecoder().decode(ParityMatrix.self, from: Data(contentsOf: url))
    }

    private static func fixture(root: URL, name: String) throws -> String {
        let url = root.appendingPathComponent("Tests/SCMAKitTests/Fixtures/DebtmapParity/")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func validate(_ matrix: ParityMatrix, repositoryRoot: URL) throws {
        guard matrix.schemaVersion == 1 else { throw ParityValidationError.unsupportedSchema }
        guard !matrix.debtmapVersion.isEmpty else { throw ParityValidationError.missingVersion }
        guard !matrix.capabilities.isEmpty else { throw ParityValidationError.emptyMatrix }

        var seen: Set<String> = []
        for capability in matrix.capabilities {
            guard !capability.id.isEmpty else { throw ParityValidationError.blankCapabilityID }
            guard seen.insert(capability.id).inserted else {
                throw ParityValidationError.duplicateCapability(capability.id)
            }
            guard capability.status == .outOfScope || !capability.proof.isEmpty else {
                throw ParityValidationError.missingProof(capability.id)
            }
            for reference in capability.proof {
                let path = reference.split(separator: "#", maxSplits: 1).first.map(String.init) ?? reference
                guard !path.isEmpty else { throw ParityValidationError.missingProof(capability.id) }
                guard FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(path).path) else {
                    throw ParityValidationError.missingProofFile(reference)
                }
            }
        }
    }
}
