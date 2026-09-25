import Foundation
import SwiftDebtLifecycle

enum LifecycleCLIRequest {
    case inventory(artifactPath: String, format: LifecycleReadFormat)
    case explain(artifactPath: String, findingID: FindingID, format: LifecycleReadFormat)
    case snapshot(artifactPath: String, snapshotID: SnapshotID, format: LifecycleReadFormat)

    func run() throws -> String {
        let service = LifecycleReadService()
        switch self {
        case .inventory(let artifactPath, let format):
            return try service.inventory(at: URL(fileURLWithPath: artifactPath), format: format)
        case .explain(let artifactPath, let findingID, let format):
            return try service.explain(
                findingID: findingID,
                at: URL(fileURLWithPath: artifactPath),
                format: format
            )
        case .snapshot(let artifactPath, let snapshotID, let format):
            return try service.inspect(
                snapshotID: snapshotID,
                at: URL(fileURLWithPath: artifactPath),
                format: format
            )
        }
    }
}

extension CLIOptions {
    func parseLifecycle(_ arguments: [String]) throws -> CLIAction {
        guard let command = arguments.first else {
            throw CLIError("Expected lifecycle inventory, explain, or snapshot")
        }
        var positional: [String] = []
        var format = LifecycleReadFormat.text
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
                let value = String(argument.dropFirst("--format=".count))
                guard let parsed = LifecycleReadFormat(rawValue: value) else {
                    throw CLIError("Invalid lifecycle format: \(value)")
                }
                format = parsed
                continue
            }
            if !literal && argument == "--format" {
                guard index < arguments.count,
                    let parsed = LifecycleReadFormat(rawValue: arguments[index])
                else {
                    throw CLIError("Lifecycle format must be text or json")
                }
                format = parsed
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
                throw CLIError("Usage: swift-debt lifecycle inventory ARTIFACT [--format text|json]")
            }
            return .lifecycle(.inventory(artifactPath: positional[0], format: format))
        case "explain":
            guard positional.count == 2 else {
                throw CLIError("Usage: swift-debt lifecycle explain ARTIFACT FINDING_ID [--format text|json]")
            }
            do {
                return .lifecycle(
                    .explain(
                        artifactPath: positional[0],
                        findingID: try FindingID(positional[1]),
                        format: format
                    )
                )
            } catch {
                throw CLIError(String(describing: error))
            }
        case "snapshot":
            guard positional.count == 2 else {
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
