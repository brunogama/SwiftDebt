import Foundation

struct ParityMatrix: Decodable {
    let debtmapVersion: String
    let matrixSchemaVersion: Int
    let statuses: [String]
    let statusDefinition: [String: String]
    let validation: ParityValidation
    let capabilities: [ParityCapability]
}

struct ParityValidation: Decodable {
    let testFilter: String
}

struct ParityCapability: Decodable {
    let id: String
    let ownerTicket: String?
    let implementationState: String
    let scope: String
    let status: String
    let proofs: [ParityProof]
}

struct ParityProof: Decodable {
    let kind: String
    let reference: String
}

struct ReleaseGateEvidence: Decodable {
    let schemaVersion: Int
    let generatedAt: String
    let gates: [ReleaseGateResult]
}

struct ReleaseGateResult: Decodable {
    let id: String
    let command: String
    let observedAt: String
    let status: String
    let exitStatus: Int
    let stdoutSummary: String
    let evidencePath: String?
}

struct PerformanceEvidenceReport: Decodable {
    let items: [PerformanceEvidenceItem]
}

struct PerformanceEvidenceItem: Decodable {
    let evidence: [PerformanceEvidenceFact]
}

struct PerformanceEvidenceFact: Decodable {
    let kind: String
    let availability: PerformanceEvidenceAvailability
}

struct PerformanceEvidenceAvailability: Decodable {
    let state: String
}

struct BenchmarkMethodology: Decodable {
    let frozenInputProvenanceCommit: String
    let performanceReferenceCommit: String
    let schemaVersion: Int
    let outputDirectory: String
    let warmupRuns: Int
    let measuredRuns: Int
    let measurements: [String]
    let methodology: [String]
    let inputs: [BenchmarkInput]
    let commands: [BenchmarkCommand]
    let performanceGate: BenchmarkPerformanceGate
    let platformVariance: BenchmarkPlatformVariance
    let regressionBudgets: [BenchmarkRegressionBudget]
}

struct BenchmarkInput: Decodable {
    let path: String
    let sha256: String
    let utf8ByteCount: Int
    let lineCount: Int
}

struct BenchmarkCommand: Decodable {
    let name: String
    let argv: [String]
}

struct BenchmarkPerformanceGate: Decodable {
    let comparisonUnit: String
    let referenceRequirements: [String]
    let disallowedComparisons: [String]
    let approvedExceptionEvidence: [String]
}

struct BenchmarkPlatformVariance: Decodable {
    let ciUsage: String
    let noiseControls: [String]
    let requiredMetadata: [String]
}

struct BenchmarkRegressionBudget: Decodable {
    let name: String
    let analysisMode: String
    let optionalContext: String
    let workloadFamily: String
    let maximumWallClockRegressionPercent: Double
    let maximumWallClockRegressionSeconds: Double?
    let maximumPeakMemoryRegressionPercent: Double
    let maximumPeakMemoryRegressionBytes: UInt64?
}

struct GoldenFixture: Decodable {
    let schemaVersion: Int
    let generatedAt: String
    let gitHistory: GitHistoryFixture
    let evidenceAvailability: [EvidenceAvailabilityFixture]
    let items: [DebtItemFixture]
    let graphEdges: [GraphEdgeFixture]
    let cliCases: [CLICaseFixture]

    func shuffledForDeterminismCheck() -> GoldenFixture {
        GoldenFixture(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            gitHistory: gitHistory.reversedCommits(),
            evidenceAvailability: Array(evidenceAvailability.reversed()),
            items: Array(items.reversed()),
            graphEdges: Array(graphEdges.reversed()),
            cliCases: Array(cliCases.reversed())
        )
    }
}

struct GitHistoryFixture: Decodable {
    let referenceTime: String
    let commits: [GitCommitFixture]

    func reversedCommits() -> GitHistoryFixture {
        GitHistoryFixture(referenceTime: referenceTime, commits: Array(commits.reversed()))
    }
}

struct GitCommitFixture: Decodable {
    let sha: String
    let authorId: String
    let timestamp: String
    let paths: [String]
}

struct EvidenceAvailabilityFixture: Decodable, Encodable {
    let id: String
    let state: String
    let reason: String?
}

struct DebtItemFixture: Decodable, Encodable {
    let id: String
    let entity: String
    let priority: String
    let score: Double
    let location: String
    let evidence: [String]
}

struct GraphEdgeFixture: Decodable {
    let source: String
    let target: String
    let label: String
}

struct CLICaseFixture: Decodable, Encodable {
    let command: String
    let exitStatus: Int
    let purpose: String
}

private struct GoldenReport: Encodable {
    let schemaVersion: Int
    let generatedAt: String
    let referenceTime: String
    let evidenceAvailability: [EvidenceAvailabilityFixture]
    let items: [DebtItemFixture]
}

func renderJSON(_ fixture: GoldenFixture) throws -> String {
    let report = GoldenReport(
        schemaVersion: fixture.schemaVersion,
        generatedAt: fixture.generatedAt,
        referenceTime: fixture.gitHistory.referenceTime,
        evidenceAvailability: fixture.evidenceAvailability.sorted { $0.id < $1.id },
        items: fixture.items.sorted { $0.id < $1.id }
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
}

func renderMarkdown(_ fixture: GoldenFixture) -> String {
    var lines = [
        "# Debtmap fixture report",
        "",
        "Generated: \(fixture.generatedAt)",
        "Reference time: \(fixture.gitHistory.referenceTime)",
        "",
        "## Evidence availability",
        "",
    ]
    for evidence in fixture.evidenceAvailability.sorted(by: { $0.id < $1.id }) {
        let reason = evidence.reason.map { " - \($0)" } ?? ""
        lines.append("- \(evidence.id): \(evidence.state)\(reason)")
    }
    lines += ["", "## Ranked items", ""]
    for item in fixture.items.sorted(by: { $0.id < $1.id }) {
        let score = String(
            format: "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            item.score
        )
        lines.append("- \(item.priority) \(item.entity) score \(score) at \(item.location)")
    }
    return lines.joined(separator: "\n") + "\n"
}

func renderDOT(_ fixture: GoldenFixture) -> String {
    var lines = ["digraph DebtmapFixture {", "  rankdir=LR;"]
    for edge in fixture.graphEdges.sorted(by: { lhs, rhs in
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        if lhs.target != rhs.target { return lhs.target < rhs.target }
        return lhs.label < rhs.label
    }) {
        lines.append("  \"\(edge.source)\" -> \"\(edge.target)\" [label=\"\(edge.label)\"];")
    }
    lines.append("}")
    return lines.joined(separator: "\n") + "\n"
}

func renderCLI(_ fixture: GoldenFixture) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let cases = fixture.cliCases.sorted { $0.command < $1.command }
    return String(decoding: try encoder.encode(cases), as: UTF8.self) + "\n"
}
