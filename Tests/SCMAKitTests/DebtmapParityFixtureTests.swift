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
        let requiredOwnerTickets = Set((6...21).map { String(format: "%02d", $0) })
        let representedOwnerTickets = Set(
            matrix.capabilities.compactMap(\.ownerTicket).compactMap { $0.split(separator: "-").first.map(String.init) }
        )
        #expect(
            requiredOwnerTickets.isSubset(of: representedOwnerTickets),
            "Parity matrix omits ticket capabilities: \(requiredOwnerTickets.subtracting(representedOwnerTickets).sorted())"
        )

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

    @Test func finalReleaseAcceptanceRequiresClosedParityEvidence() throws {
        let matrix: ParityMatrix = try loadJSON("docs/debtmap/parity-matrix.v0.23.0.json")
        let readme = try read("README.md")
        let releaseAcceptance = try read("docs/debtmap/release-quality-acceptance.md")
        let parityClaim = "Debtmap 0.23.0 workflow/capability parity for Swift"
        let inScope = matrix.capabilities.filter { $0.scope == "in-scope" }
        let declaredTestProofReferences = try declaredTestProofReferences()

        #expect(!inScope.isEmpty)
        #expect(readme.contains(parityClaim))
        #expect(releaseAcceptance.contains(parityClaim))
        #expect(releaseAcceptance.contains("No approved exceptions were recorded for required gates."))

        for capability in inScope {
            #expect(capability.implementationState == "implemented", "Open implementation for \(capability.id)")
            #expect(capability.status == "implemented" || capability.status == "intentional-divergence")
            for proof in capability.proofs where proof.kind == "test" {
                #expect(
                    declaredTestProofReferences.contains(proof.reference),
                    "Unresolved test proof for \(capability.id): \(proof.reference)"
                )
            }
            #expect(
                capability.proofs.contains {
                    $0.kind == "test" && declaredTestProofReferences.contains($0.reference)
                },
                "Missing executable test proof for \(capability.id)"
            )
            #expect(
                !capability.proofs.contains { $0.kind == "ticket" },
                "Ticket planning reference is not release proof for \(capability.id)"
            )
            if capability.status == "intentional-divergence" {
                #expect(
                    capability.proofs.contains {
                        $0.kind == "documentation"
                            && $0.reference == "docs/debtmap/release-quality-acceptance.md"
                    },
                    "Missing documented divergence for \(capability.id)"
                )
            }
        }
    }

    @Test func requiredRegressionGatesHavePassingReleaseEvidence() throws {
        let matrix: ParityMatrix = try loadJSON("docs/debtmap/parity-matrix.v0.23.0.json")
        let evidence: ReleaseGateEvidence = try loadJSON("docs/debtmap/release-gate-evidence.v1.json")
        let regressionGates = try #require(matrix.capabilities.first { $0.id == "scma-regression-gates" })
        let requiredCommands = [
            "swift build --build-tests && swift test",
            "python3 scripts/smoke-test.py --binary .build/debug/scma --plugins",
        ]

        #expect(evidence.schemaVersion == 1)
        #expect(!evidence.generatedAt.isEmpty)
        #expect(
            regressionGates.proofs.contains {
                $0.kind == "gate-evidence" && $0.reference == "docs/debtmap/release-gate-evidence.v1.json"
            }
        )
        #expect(
            Set(evidence.gates.map(\.id)) == Set(["swift-build-tests-and-test-suite", "scma-plugin-smoke-test"])
        )

        for command in requiredCommands {
            let gate = try #require(evidence.gates.first { $0.command == command })
            #expect(gate.status == "passed")
            #expect(gate.exitStatus == 0)
            #expect(!gate.observedAt.isEmpty)
            #expect(gate.stdoutSummary.contains("pass") || gate.stdoutSummary.contains("PASS"))
        }
    }

    @Test func goldenFixtureOutputsRemainDeterministic() throws {
        let fixture: GoldenFixture = try loadJSON(
            "Tests/SCMAKitTests/Fixtures/DebtmapParity/canonical-workflow.fixture.json")

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
        let workflow = try read(".github/workflows/debtmap-performance.yml")

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
        #expect(
            methodology.performanceGate.approvedExceptionEvidence.contains(
                "written justification for accepting the regression"))
        #expect(methodology.regressionBudgets.map(\.name) == ["baseline-analysis", "full-evidence-analysis"])
        #expect(methodology.regressionBudgets.allSatisfy { $0.workloadFamily == "SwiftSCMA" })
        #expect(methodology.regressionBudgets.map(\.maximumPeakMemoryRegressionPercent) == [15, 15])
        #expect(methodology.regressionBudgets[0].maximumWallClockRegressionPercent == 10)
        #expect(methodology.regressionBudgets[0].optionalContext == "none")
        #expect(methodology.regressionBudgets[1].maximumWallClockRegressionPercent == 20)
        #expect(methodology.regressionBudgets[1].optionalContext == "coverage-and-repository-history")
        #expect(workflow.contains("scripts/run_debtmap_benchmark.py"))
        #expect(workflow.contains("scma performance-gate"))
        #expect(workflow.contains(methodology.baselineCommit))
        #expect(workflow.contains("--max-wall-clock-regression 10"))
        #expect(workflow.contains("--max-peak-memory-regression 15"))

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

    private func declaredTestProofReferences() throws -> Set<String> {
        let testsRoot = root.appendingPathComponent("Tests")
        var references = Set<String>()
        guard
            let enumerator = FileManager.default.enumerator(
                at: testsRoot,
                includingPropertiesForKeys: nil
            )
        else {
            return references
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for suite in try declaredSuites(in: source) {
                for test in try declaredTests(in: source) {
                    references.insert("\(suite).\(test)")
                }
            }
        }

        return references
    }

    private func declaredSuites(in source: String) throws -> [String] {
        try captureGroups(
            pattern:
                #"@Suite(?:\([^)]*\))?\s+(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*(?:struct|final\s+class|class|actor)\s+([A-Za-z_][A-Za-z0-9_]*)\b"#,
            source: source
        )
    }

    private func declaredTests(in source: String) throws -> [String] {
        try captureGroups(
            pattern:
                #"@Test(?:\([^)]*\))?\s+(?:@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s+)*func\s+([A-Za-z_][A-Za-z0-9_]*)\b"#,
            source: source
        )
    }

    private func captureGroups(pattern: String, source: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[captureRange])
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
