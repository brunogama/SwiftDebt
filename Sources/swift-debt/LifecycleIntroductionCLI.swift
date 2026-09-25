import SwiftDebtLifecycle

extension CLIOptions {
    func parseLifecycleIntroduction(_ arguments: [String]) throws -> CLIAction {
        var positional: [String] = []
        var values: [String: String] = [:]
        var literal = false
        var index = 0
        let valuedOptions: Set<String> = [
            "--repository", "--max-revisions", "--max-file-bytes", "--format",
        ]
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if !literal, argument == "--" {
                literal = true
                continue
            }
            if !literal, argument.hasPrefix("-") {
                let split = argument.split(
                    separator: "=",
                    maxSplits: 1,
                    omittingEmptySubsequences: false
                ).map(String.init)
                let key = split[0]
                guard valuedOptions.contains(key) else {
                    throw CLIError("Unknown lifecycle option: \(key)")
                }
                let value: String
                if split.count == 2 {
                    value = split[1]
                } else {
                    guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                        throw CLIError("Missing value for \(key)")
                    }
                    value = arguments[index]
                    index += 1
                }
                guard !value.isEmpty else { throw CLIError("Empty value for \(key)") }
                guard values[key] == nil else { throw CLIError("Duplicate option: \(key)") }
                values[key] = value
                continue
            }
            positional.append(argument)
        }

        guard positional.count == 2,
            let repository = values["--repository"],
            let revisionLimit = values["--max-revisions"],
            let maximumRevisions = Int(revisionLimit), maximumRevisions > 0
        else {
            throw CLIError(
                "Usage: swift-debt lifecycle infer-introduction ARTIFACT FINDING_ID "
                    + "--repository PATH --max-revisions INTEGER [--max-file-bytes INTEGER] "
                    + "[--format text|json]"
            )
        }
        let maximumFileBytes: Int
        if let value = values["--max-file-bytes"] {
            guard let parsed = Int(value), parsed > 0 else {
                throw CLIError("max-file-bytes must be a positive integer")
            }
            maximumFileBytes = parsed
        } else {
            maximumFileBytes = 16 * 1_024 * 1_024
        }
        let format: LifecycleReadFormat
        if let value = values["--format"] {
            guard let parsed = LifecycleReadFormat(rawValue: value) else {
                throw CLIError("Lifecycle format must be text or json")
            }
            format = parsed
        } else {
            format = .text
        }
        do {
            return .lifecycle(
                .inferIntroduction(
                    artifactPath: positional[0],
                    findingID: try FindingID(positional[1]),
                    repositoryPath: repository,
                    maximumRevisions: maximumRevisions,
                    maximumFileBytes: maximumFileBytes,
                    format: format
                )
            )
        } catch {
            throw CLIError(String(describing: error))
        }
    }
}
