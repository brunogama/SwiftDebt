import Foundation
import PackagePlugin

@main
struct SCMACommandPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // ArgumentExtractor is the package-plugin argument boundary; analysis flags go to the CLI.
        try validateTargets(arguments)
        var extractor = ArgumentExtractor(arguments)
        let names = Set(extractor.extractOption(named: "target"))
        let includeTests = extractor.extractFlag(named: "include-tests") > 0
        let allTargets = context.package.targets.compactMap { $0 as? SwiftSourceModuleTarget }
        let missing = names.subtracting(allTargets.map(\.name))
        guard missing.isEmpty else {
            throw PluginFailure("Unknown Swift targets: \(missing.sorted().joined(separator: ", "))")
        }
        let selected = allTargets.filter {
            names.isEmpty ? (includeTests || $0.kind != .test) : names.contains($0.name)
        }
        let sources = selected.flatMap { target in
            target.sourceFiles.filter { $0.url.pathExtension == "swift" }.map {
                Entry(path: $0.url.path, module: target.moduleName)
            }
        }.sorted { $0.path < $1.path }
        guard !sources.isEmpty else { throw PluginFailure("No Swift source files in selected targets") }
        let directory = context.pluginWorkDirectoryURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = directory.appendingPathComponent("inputs.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Manifest(root: context.package.directoryURL.path, sources: sources))
        if (try? Data(contentsOf: manifest)) != data { try data.write(to: manifest, options: .atomic) }
        let process = Process()
        process.executableURL = try context.tool(named: "scma").url
        process.arguments = scmaArguments(manifest: manifest.path, remaining: extractor.remainingArguments)
        process.currentDirectoryURL = context.package.directoryURL
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit && process.terminationStatus == 0 else {
            throw PluginFailure("SCMA failed with exit status \(process.terminationStatus)")
        }
    }

    private func scmaArguments(manifest: String, remaining: [String]) -> [String] {
        let command = Array(remaining.prefix(2))
        if command == ["debt", "analyze"] || command == ["debt", "validate"] {
            return Array(remaining.prefix(2)) + ["--manifest", manifest, "--plugin-evidence-limitations"]
                + Array(remaining.dropFirst(2))
        }
        let analysisArguments = remaining.first == "analyze" ? Array(remaining.dropFirst()) : remaining
        return ["analyze", "--manifest", manifest, "--plugin-evidence-limitations"] + analysisArguments
    }

    private func validateTargets(_ arguments: [String]) throws {
        // ArgumentExtractor otherwise silently consumes a missing final --target value.
        for (index, argument) in arguments.enumerated() {
            if argument == "--" { break }
            if argument == "--target" {
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                    throw PluginFailure("--target requires a target name")
                }
            }
            if argument == "--target=" { throw PluginFailure("--target requires a target name") }
            if argument == "--manifest" || argument.hasPrefix("--manifest=")
                || argument == "--stamp" || argument.hasPrefix("--stamp=")
            {
                throw PluginFailure("--manifest and --stamp are reserved by the plugin")
            }
        }
    }

    private struct Entry: Encodable {
        let path: String
        let module: String
    }
    private struct Manifest: Encodable {
        let root: String
        let sources: [Entry]
    }
    private struct PluginFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
