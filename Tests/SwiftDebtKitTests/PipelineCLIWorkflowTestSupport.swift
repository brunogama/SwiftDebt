import Foundation

let pipelineCLIKnownPullRequestChecks = [
    "staticAnalysis", "architecture", "unit", "integration", "regression", "endToEnd",
]

struct PipelineCLICommandFixture {
    let check: String
    var executable: String
    var arguments: [String]
    var timeoutSeconds: Double

    init(
        check: String,
        executable: String = "/bin/sh",
        arguments: [String],
        timeoutSeconds: Double = 2
    ) {
        self.check = check
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }
}

struct PipelineCLIObservedContext: Codable, Equatable {
    let risk: String
    let trigger: String
    let impact: String
}

struct PipelineCLIObservedRequirement: Codable, Equatable {
    let check: String
    let required: Bool
    let reason: String
}

struct PipelineCLIObservedPlan: Codable, Equatable {
    let policyRevision: Int
    let context: PipelineCLIObservedContext
    let requirements: [PipelineCLIObservedRequirement]
}

struct PipelineCLIObservedResult: Codable, Equatable {
    let check: String
    let status: String
    let detail: String
}

struct PipelineCLIObservedEvaluation: Codable, Equatable {
    let verdict: String
    let results: [PipelineCLIObservedResult]
}

struct PipelineCLIObservedReport: Codable, Equatable {
    let schemaVersion: Int
    let plan: PipelineCLIObservedPlan
    let evaluation: PipelineCLIObservedEvaluation
}

func pipelineCLIPassingCommands() -> [PipelineCLICommandFixture] {
    pipelineCLIKnownPullRequestChecks.map { check in
        PipelineCLICommandFixture(
            check: check,
            arguments: [
                "-c", "printf '\(check)-stdout\\n'; printf '\(check)-stderr\\n' >&2",
            ])
    }
}

func makePipelineCLITemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swift-debt-pipeline-cli-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
    return directory
}

func writePipelineCLIConfiguration(
    at url: URL,
    schemaVersion: Int = 1,
    commands: [PipelineCLICommandFixture],
    risk: String = "low",
    trigger: String = "pullRequest",
    impact: String = "known"
) throws {
    let object: [String: Any] = [
        "schemaVersion": schemaVersion,
        "context": ["risk": risk, "trigger": trigger, "impact": impact],
        "commands": commands.map { command in
            [
                "check": command.check,
                "executable": command.executable,
                "arguments": command.arguments,
                "timeoutSeconds": command.timeoutSeconds,
            ] as [String: Any]
        },
    ]
    let data = try JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: url, options: .atomic)
}

func decodePipelineCLIJSON<Value: Decodable>(
    _ type: Value.Type, from output: String
) throws -> Value {
    try JSONDecoder().decode(type, from: Data(output.utf8))
}

func canonicalPipelineCLIJSON<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
}

func readPipelineCLIText(_ url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}
