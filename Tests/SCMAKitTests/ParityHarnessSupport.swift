import Foundation

struct ParityMatrix: Codable, Equatable {
    var schemaVersion: Int
    var debtmapVersion: String
    var swiftSCMABaselineVersion: String
    var capabilities: [ParityCapability]
}

struct ParityCapability: Codable, Equatable {
    var id: String
    var title: String
    var status: CapabilityStatus
    var proof: [String]
    var notes: String
}

enum CapabilityStatus: String, Codable, Equatable {
    case implemented
    case intentionalDivergence = "intentional-divergence"
    case outOfScope = "out-of-scope"
}

enum ParityValidationError: Error, Equatable {
    case unsupportedSchema
    case missingVersion
    case emptyMatrix
    case blankCapabilityID
    case duplicateCapability(String)
    case missingProof(String)
    case missingProofFile(String)
}

struct GoldenFixture: Equatable {
    var frozenClock: String
    var evidenceAvailable: Bool
    var capabilities: [GoldenCapability]
    var history: [GoldenGitEdge]

    static func unordered() -> GoldenFixture {
        GoldenFixture(
            frozenClock: "2026-01-02T03:04:05Z",
            evidenceAvailable: false,
            capabilities: [
                GoldenCapability(id: "debtmap.output.markdown", status: "implemented"),
                GoldenCapability(id: "debtmap.output.json", status: "implemented"),
                GoldenCapability(id: "debtmap.baseline.methodology", status: "implemented"),
                GoldenCapability(id: "debtmap.output.dot", status: "implemented"),
            ],
            history: [
                GoldenGitEdge(parent: "1111111", child: "2222222"),
                GoldenGitEdge(parent: "0000000", child: "1111111"),
            ]
        )
    }

    static func reversed() -> GoldenFixture {
        var fixture = unordered()
        fixture.capabilities.reverse()
        fixture.history.reverse()
        return fixture
    }
}

struct GoldenCapability: Equatable {
    var id: String
    var status: String
}

struct GoldenGitEdge: Equatable {
    var parent: String
    var child: String
}

enum GoldenFixtureRenderer {
    static func json(_ fixture: GoldenFixture) -> String {
        let capabilities = fixture.capabilities.sorted { $0.id < $1.id }
        let history = fixture.history.sorted { lhs, rhs in
            lhs.parent == rhs.parent ? lhs.child < rhs.child : lhs.parent < rhs.parent
        }
        let evidence = fixture.evidenceAvailable ? "available" : "unavailable"
        var lines = ["{"]
        lines.append("  \"capabilities\": [")
        for (index, capability) in capabilities.enumerated() {
            lines.append("    {")
            lines.append("      \"id\": \"\(capability.id)\",")
            lines.append("      \"status\": \"\(capability.status)\"")
            lines.append("    }" + (index == capabilities.count - 1 ? "" : ","))
        }
        lines.append("  ],")
        lines.append("  \"evidence\": \"\(evidence)\",")
        lines.append("  \"frozenClock\": \"\(fixture.frozenClock)\",")
        lines.append("  \"gitHistory\": [")
        for (index, edge) in history.enumerated() {
            lines.append("    {")
            lines.append("      \"child\": \"\(edge.child)\",")
            lines.append("      \"parent\": \"\(edge.parent)\"")
            lines.append("    }" + (index == history.count - 1 ? "" : ","))
        }
        lines.append("  ]")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    static func markdown(_ fixture: GoldenFixture) -> String {
        let capabilities = fixture.capabilities.sorted { $0.id < $1.id }
        let history = fixture.history.sorted { lhs, rhs in
            lhs.parent == rhs.parent ? lhs.child < rhs.child : lhs.parent < rhs.parent
        }
        let evidence = fixture.evidenceAvailable ? "available" : "unavailable"
        var lines = [
            "# Debtmap parity fixture",
            "",
            "Frozen clock: \(fixture.frozenClock)",
            "Evidence: \(evidence)",
            "",
            "| Capability | Status |",
            "| --- | --- |",
        ]
        lines += capabilities.map { "| \($0.id) | \($0.status) |" }
        lines += ["", "## Git history", ""]
        lines += history.map { "- \($0.parent) -> \($0.child)" }
        return lines.joined(separator: "\n") + "\n"
    }

    static func dot(_ fixture: GoldenFixture) -> String {
        let capabilities = fixture.capabilities.sorted { $0.id < $1.id }
        let history = fixture.history.sorted { lhs, rhs in
            lhs.parent == rhs.parent ? lhs.child < rhs.child : lhs.parent < rhs.parent
        }
        var lines = ["digraph DebtmapParity {"]
        lines += history.map { "  \"\($0.parent)\" -> \"\($0.child)\";" }
        lines += capabilities.map { "  \"\($0.id)\" [label=\"\($0.status)\"];" }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    static func cliExit(_ fixture: GoldenFixture) -> String {
        if fixture.evidenceAvailable {
            return "exitStatus=0\nstderr=\n"
        }
        return "exitStatus=2\nstderr=Debtmap evidence unavailable for frozen fixture at \(fixture.frozenClock)\n"
    }
}

struct BenchmarkManifest: Codable, Equatable {
    var schemaVersion: Int
    var baselineName: String
    var baselineDate: String
    var purpose: String
    var inputs: [BenchmarkInput]
    var configuration: BenchmarkConfiguration
    var metrics: [String]
    var runs: BenchmarkRuns
    var measurementCommands: [String]
}

struct BenchmarkInput: Codable, Equatable {
    var path: String
    var utf8ByteCount: Int
    var lineCount: Int
    var module: String
}

struct BenchmarkConfiguration: Codable, Equatable {
    var format: String
    var typeScope: String
    var scoring: String
    var jobs: Int
}

struct BenchmarkRuns: Codable, Equatable {
    var warmup: Int
    var measured: Int
    var reportedStatistic: String
}
