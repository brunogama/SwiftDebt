import Foundation
import SwiftDebtKit
import SwiftDebtLifecycle

enum LifecycleCLIRequest {
    case inventory(artifactPath: String, headSnapshotID: SnapshotID?, format: LifecycleReadFormat)
    case explain(
        artifactPath: String,
        findingID: FindingID,
        headSnapshotID: SnapshotID?,
        format: LifecycleReadFormat
    )
    case snapshot(artifactPath: String, snapshotID: SnapshotID, format: LifecycleReadFormat)
    case inferIntroduction(
        artifactPath: String,
        findingID: FindingID,
        repositoryPath: String,
        maximumRevisions: Int,
        maximumFileBytes: Int,
        format: LifecycleReadFormat
    )

    func run() throws -> String {
        let service = LifecycleReadService()
        switch self {
        case .inventory(let artifactPath, let headSnapshotID, let format):
            return try service.inventory(
                at: URL(fileURLWithPath: artifactPath),
                headSnapshotID: headSnapshotID,
                format: format
            )
        case .explain(let artifactPath, let findingID, let headSnapshotID, let format):
            return try service.explain(
                findingID: findingID,
                at: URL(fileURLWithPath: artifactPath),
                headSnapshotID: headSnapshotID,
                format: format
            )
        case .snapshot(let artifactPath, let snapshotID, let format):
            return try service.inspect(
                snapshotID: snapshotID,
                at: URL(fileURLWithPath: artifactPath),
                format: format
            )
        case .inferIntroduction(
            let artifactPath,
            let findingID,
            let repositoryPath,
            let maximumRevisions,
            let maximumFileBytes,
            let format
        ):
            let artifactURL = URL(fileURLWithPath: artifactPath)
            _ = try LifecycleIntroductionService().infer(
                LifecycleIntroductionRequest(
                    artifactURL: artifactURL,
                    repositoryURL: URL(fileURLWithPath: repositoryPath),
                    findingID: findingID,
                    maximumRevisions: maximumRevisions,
                    maximumFileBytes: maximumFileBytes
                )
            )
            return try service.explain(findingID: findingID, at: artifactURL, format: format)
        }
    }
}

extension CLIOptions {
    func parseLifecycle(_ arguments: [String]) throws -> CLIAction {
        guard let command = arguments.first else {
            throw CLIError("Expected lifecycle inventory, explain, snapshot, or infer-introduction")
        }
        if command == "infer-introduction" {
            return try parseLifecycleIntroduction(Array(arguments.dropFirst()))
        }
        var positional: [String] = []
        var format = LifecycleReadFormat.text
        var sawFormat = false
        var headSnapshotID: SnapshotID?
        var index = 1
        var literal = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if !literal && argument == "--" {
                literal = true
                continue
            }
            if !literal && argument.hasPrefix("--format=") {
                guard !sawFormat else { throw CLIError("Duplicate option: --format") }
                let value = String(argument.dropFirst("--format=".count))
                guard let parsed = LifecycleReadFormat(rawValue: value) else {
                    throw CLIError("Invalid lifecycle format: \(value)")
                }
                format = parsed
                sawFormat = true
                continue
            }
            if !literal && argument == "--format" {
                guard !sawFormat else { throw CLIError("Duplicate option: --format") }
                guard index < arguments.count,
                    let parsed = LifecycleReadFormat(rawValue: arguments[index])
                else {
                    throw CLIError("Lifecycle format must be text or json")
                }
                format = parsed
                sawFormat = true
                index += 1
                continue
            }
            if !literal && argument.hasPrefix("--head=") {
                guard headSnapshotID == nil else { throw CLIError("Duplicate option: --head") }
                do {
                    headSnapshotID = try SnapshotID(String(argument.dropFirst("--head=".count)))
                } catch {
                    throw CLIError(String(describing: error))
                }
                continue
            }
            if !literal && argument == "--head" {
                guard headSnapshotID == nil else { throw CLIError("Duplicate option: --head") }
                guard index < arguments.count else { throw CLIError("Missing value for --head") }
                do {
                    headSnapshotID = try SnapshotID(arguments[index])
                } catch {
                    throw CLIError(String(describing: error))
                }
                index += 1
                continue
            }
            if !literal && argument.hasPrefix("-") {
                throw CLIError("Unknown lifecycle option: \(argument)")
            }
            positional.append(argument)
        }

        switch command {
        case "inventory":
            guard positional.count == 1 else {
                throw CLIError(
                    "Usage: swift-debt lifecycle inventory ARTIFACT [--head SNAPSHOT_ID] [--format text|json]")
            }
            return .lifecycle(
                .inventory(artifactPath: positional[0], headSnapshotID: headSnapshotID, format: format)
            )
        case "explain":
            guard positional.count == 2 else {
                throw CLIError(
                    "Usage: swift-debt lifecycle explain ARTIFACT FINDING_ID "
                        + "[--head SNAPSHOT_ID] [--format text|json]"
                )
            }
            do {
                return .lifecycle(
                    .explain(
                        artifactPath: positional[0],
                        findingID: try FindingID(positional[1]),
                        headSnapshotID: headSnapshotID,
                        format: format
                    )
                )
            } catch {
                throw CLIError(String(describing: error))
            }
        case "snapshot":
            guard positional.count == 2, headSnapshotID == nil else {
                throw CLIError("Usage: swift-debt lifecycle snapshot ARTIFACT SNAPSHOT_ID [--format text|json]")
            }
            do {
                return .lifecycle(
                    .snapshot(
                        artifactPath: positional[0],
                        snapshotID: try SnapshotID(positional[1]),
                        format: format
                    )
                )
            } catch {
                throw CLIError(String(describing: error))
            }
        default:
            throw CLIError("Unknown lifecycle command: \(command)")
        }
    }
}
