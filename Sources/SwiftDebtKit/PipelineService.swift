import Foundation
import SwiftDebtCore

/// Plans and executes local verification checks, retaining auditable artifacts.
public struct PipelineService: Sendable {
    /// Creates a stateless pipeline service.
    public init() {}

    /// Validates configuration and derives a canonical plan without executing commands.
    public func plan(configuration: PipelineConfiguration) throws -> PipelinePlan {
        try validate(configuration)
        return PipelinePlanner.plan(context: configuration.context)
    }

    /// Runs planned checks serially in `workingDirectory`.
    ///
    /// The artifact directory must be new. The service writes the configuration
    /// and plan first, each result atomically after its check, and the final report
    /// last. Execution failures remain evidence; filesystem failures throw.
    /// Only directly launched processes are supervised on macOS and Linux.
    public func run(
        configuration: PipelineConfiguration,
        workingDirectory: URL,
        artifactsDirectory: URL
    ) throws -> PipelineRunReport {
        let plan = try plan(configuration: configuration)
        guard !FileManager.default.fileExists(atPath: artifactsDirectory.path) else {
            throw PipelineServiceError.artifactsAlreadyExist(artifactsDirectory.path)
        }

        try FileManager.default.createDirectory(
            at: artifactsDirectory,
            withIntermediateDirectories: false
        )
        try writeJSON(
            configuration,
            to: artifactsDirectory.appendingPathComponent("configuration.json")
        )

        try writeJSON(plan, to: artifactsDirectory.appendingPathComponent("plan.json"))

        let results = try collectResults(
            plan: plan,
            configuration: configuration,
            workingDirectory: workingDirectory,
            artifactsDirectory: artifactsDirectory
        )

        let report = PipelineRunReport(
            schemaVersion: 1,
            plan: plan,
            evaluation: PipelineEvaluator.evaluate(plan: plan, results: results)
        )
        try writeJSON(report, to: artifactsDirectory.appendingPathComponent("report.json"))
        return report
    }

    private func collectResults(
        plan: PipelinePlan,
        configuration: PipelineConfiguration,
        workingDirectory: URL,
        artifactsDirectory: URL
    ) throws -> [PipelineCheckResult] {
        var results: [PipelineCheckResult] = []
        for requirement in plan.requirements {
            let result: PipelineCheckResult
            if let command = configuration.commands.first(where: {
                $0.check == requirement.check
            }) {
                result = try execute(
                    command,
                    workingDirectory: workingDirectory,
                    artifactsDirectory: artifactsDirectory
                )
            } else {
                result = PipelineCheckResult(
                    check: requirement.check,
                    status: .unavailable,
                    detail: "no command configured for \(requirement.check.rawValue)"
                )
            }
            try writeJSON(
                result,
                to: artifactsDirectory.appendingPathComponent("\(requirement.check.rawValue).result.json")
            )
            results.append(result)
        }
        return results
    }

    private func validate(_ configuration: PipelineConfiguration) throws {
        guard configuration.schemaVersion == 1 else {
            throw PipelineServiceError.unsupportedSchema(configuration.schemaVersion)
        }

        var seen: [PipelineCheck] = []
        for command in configuration.commands {
            guard !seen.contains(command.check) else {
                throw PipelineServiceError.duplicateCommand(command.check)
            }
            seen.append(command.check)
            guard !command.executable.isEmpty else {
                throw PipelineServiceError.emptyExecutable(command.check)
            }
            guard command.executable.first == "/" else {
                throw PipelineServiceError.relativeExecutable(command.check)
            }
            guard !command.executable.contains("\0") else {
                throw PipelineServiceError.nulExecutable(command.check)
            }
            guard
                command.timeoutSeconds.isFinite,
                command.timeoutSeconds > 0,
                command.timeoutSeconds <= 86_400
            else {
                throw PipelineServiceError.invalidTimeout(command.check)
            }
            guard !command.arguments.contains(where: { $0.contains("\0") }) else {
                throw PipelineServiceError.nulArgument(command.check)
            }
        }
    }

    private func execute(
        _ command: PipelineCommand,
        workingDirectory: URL,
        artifactsDirectory: URL
    ) throws -> PipelineCheckResult {
        let prefix = command.check.rawValue
        let stdoutURL = artifactsDirectory.appendingPathComponent("\(prefix).stdout.log")
        let stderrURL = artifactsDirectory.appendingPathComponent("\(prefix).stderr.log")
        guard FileManager.default.createFile(atPath: stdoutURL.path, contents: nil) else {
            throw PipelineServiceError.logCreationFailed(stdoutURL.path)
        }
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        defer { try? stdout.close() }
        guard FileManager.default.createFile(atPath: stderrURL.path, contents: nil) else {
            throw PipelineServiceError.logCreationFailed(stderrURL.path)
        }
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stderr.close() }

        let result = PipelineProcessRunner().run(
            command: command,
            workingDirectory: workingDirectory,
            stdout: stdout,
            stderr: stderr
        )
        switch result {
        case .exited(0):
            return PipelineCheckResult(
                check: command.check, status: .passed, detail: "command exited with status 0")
        case .exited(let status):
            return PipelineCheckResult(
                check: command.check,
                status: .failed,
                detail: "command exited with status \(status)"
            )
        case .timedOut:
            return PipelineCheckResult(
                check: command.check,
                status: .timedOut,
                detail: "command exceeded timeout of \(command.timeoutSeconds) seconds"
            )
        case .unavailable(let detail):
            return PipelineCheckResult(
                check: command.check, status: .unavailable, detail: detail)
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

enum PipelineServiceError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchema(Int)
    case duplicateCommand(PipelineCheck)
    case emptyExecutable(PipelineCheck)
    case relativeExecutable(PipelineCheck)
    case nulExecutable(PipelineCheck)
    case invalidTimeout(PipelineCheck)
    case nulArgument(PipelineCheck)
    case artifactsAlreadyExist(String)
    case logCreationFailed(String)

    var description: String {
        switch self {
        case .unsupportedSchema(let version): "unsupported pipeline schema version \(version)"
        case .duplicateCommand(let check): "duplicate command for \(check.rawValue)"
        case .emptyExecutable(let check): "empty executable for \(check.rawValue)"
        case .relativeExecutable(let check): "executable for \(check.rawValue) must be absolute"
        case .nulExecutable(let check): "executable for \(check.rawValue) contains NUL"
        case .invalidTimeout(let check):
            "timeout for \(check.rawValue) must be finite, greater than zero, and at most 86400"
        case .nulArgument(let check): "argument for \(check.rawValue) contains NUL"
        case .artifactsAlreadyExist(let path): "artifacts directory already exists: \(path)"
        case .logCreationFailed(let path): "could not create pipeline log: \(path)"
        }
    }
}
