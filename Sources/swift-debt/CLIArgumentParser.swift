import Foundation

struct CLIArgumentSchema {
    let valuedOptions: Set<String>
    var repeatableOptions: Set<String> = []
    var flags: Set<String> = []
    var flagValues: [String: (key: String, value: String)] = [:]
    var aliases: [String: String] = [:]
}

struct ParsedCLIArguments {
    var values: [String: String] = [:]
    var repeated: [String: [String]] = [:]
    var flags: Set<String> = []
    var paths: [String] = []
    var requestedHelp = false
}

private struct OptionConsumption {
    let argument: String
    let arguments: [String]
    let schema: CLIArgumentSchema
}

extension CLIOptions {
    func parseGitExecutablePath(_ path: String?) throws -> String? {
        guard let path else { return nil }
        guard (path as NSString).isAbsolutePath else {
            throw CLIError("--git-executable requires an absolute path")
        }
        return path
    }

    func parseArguments(
        _ arguments: [String], schema: CLIArgumentSchema
    ) throws -> ParsedCLIArguments {
        var result = ParsedCLIArguments()
        var literal = false
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if literal {
                result.paths.append(argument)
            } else if argument == "--" {
                literal = true
            } else if argument == "--help" || argument == "-h" {
                result.requestedHelp = true
            } else if schema.flags.contains(argument) {
                guard result.flags.insert(argument).inserted else {
                    throw CLIError("Duplicate \(argument)")
                }
            } else if let assignment = schema.flagValues[argument] {
                try setUnique(&result.values, key: assignment.key, value: assignment.value)
            } else if argument.hasPrefix("-") {
                try consumeOption(
                    OptionConsumption(argument: argument, arguments: arguments, schema: schema),
                    index: &index, result: &result)
            } else {
                result.paths.append(argument)
            }
        }
        return result
    }

    private func consumeOption(
        _ input: OptionConsumption, index: inout Int, result: inout ParsedCLIArguments
    ) throws {
        let split = input.argument.split(
            separator: "=", maxSplits: 1, omittingEmptySubsequences: false
        ).map(String.init)
        let originalKey = split[0]
        guard input.schema.valuedOptions.contains(originalKey) else {
            throw CLIError("Unknown option: \(originalKey)")
        }
        let value = try optionValue(
            split: split, key: originalKey, arguments: input.arguments, index: &index)
        let key = input.schema.aliases[originalKey] ?? originalKey
        if input.schema.repeatableOptions.contains(originalKey) {
            result.repeated[key, default: []].append(value)
        } else {
            try setUnique(&result.values, key: key, value: value)
        }
    }

    private func optionValue(
        split: [String], key: String, arguments: [String], index: inout Int
    ) throws -> String {
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
        return value
    }
}
