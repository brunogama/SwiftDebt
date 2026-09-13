import Foundation
import PackagePlugin

@main
struct SCMABuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SwiftSourceModuleTarget else { return [] }
        return try commands(
            root: context.package.directoryURL, work: context.pluginWorkDirectoryURL,
            module: target.moduleName, files: target.sourceFiles.filter { $0.url.pathExtension == "swift" }.map(\.url),
            executable: context.tool(named: "scma").url
        )
    }

    fileprivate func commands(root: URL, work: URL, module: String, files: [URL], executable: URL) throws -> [Command] {
        let inputs = files.filter { $0.lastPathComponent != "SCMA.analysis.swift" }.sorted { $0.path < $1.path }
        guard !inputs.isEmpty else { return [] }
        let configuration = root.appendingPathComponent(".scma.json")
        guard FileManager.default.fileExists(atPath: configuration.path) else {
            throw PluginFailure(
                "SCMABuildPlugin requires \(configuration.path) before its first build (an empty {} is valid). "
                    + "This makes configuration changes explicit SwiftPM inputs. The CLI and command plugin do not require this file."
            )
        }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let manifestURL = work.appendingPathComponent("inputs.json")
        let manifest = Manifest(root: root.path, sources: inputs.map { Entry(path: $0.path, module: module) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        // Keep mtime stable so a no-op build does not rerun analysis.
        if (try? Data(contentsOf: manifestURL)) != data { try data.write(to: manifestURL, options: .atomic) }
        let stamp = work.appendingPathComponent("SCMA.analysis.swift")
        let dependencies = inputs + [manifestURL, configuration]
        let arguments = [
            "analyze", "--manifest", manifestURL.path, "--format", "diagnostics",
            "--plugin-evidence-limitations", "--stamp", stamp.path, "--config", configuration.path,
        ]
        return [
            .buildCommand(
                displayName: "SCMA metrics: \(module)", executable: executable, arguments: arguments,
                inputFiles: dependencies, outputFiles: [stamp]
            )
        ]
    }

    private struct PluginFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private struct Entry: Encodable {
        let path: String
        let module: String
    }
    private struct Manifest: Encodable {
        let root: String
        let sources: [Entry]
    }
}

#if canImport(XcodeProjectPlugin)
    import XcodeProjectPlugin

    extension SCMABuildPlugin: XcodeBuildToolPlugin {
        func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
            // These Path-based Xcode APIs are retained for compatibility with Xcode's plugin host.
            // The SwiftPM adapter above uses URL APIs. Validate this adapter on your Xcode toolchain.
            try commands(
                root: URL(fileURLWithPath: context.xcodeProject.directory.string),
                work: URL(fileURLWithPath: context.pluginWorkDirectory.string),
                module: target.displayName,
                files: target.inputFiles.filter { $0.type == .source && $0.path.extension == "swift" }
                    .map { URL(fileURLWithPath: $0.path.string) },
                executable: URL(fileURLWithPath: context.tool(named: "scma").path.string)
            )
        }
    }
#endif
