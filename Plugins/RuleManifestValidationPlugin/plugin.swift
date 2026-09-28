import Foundation
import PackagePlugin

/// Wires ``RuleManifestParser`` into a real SwiftPM build failure (R2
/// TASK-009). Runs `swift-debt-manifest-lint` as a prebuild step against the
/// committed Rule Catalog Manifest on every build of `SwiftDebtCore`; if the
/// manifest has any parse/validation errors, the lint executable exits
/// non-zero and the build fails with every offending rule named.
@main
struct RuleManifestValidationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let manifestURL = context.package.directoryURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("SwiftDebtCore")
            .appendingPathComponent("RuleCatalog")
            .appendingPathComponent("Manifest")
            .appendingPathComponent("RuleCatalogManifest.yaml")

        let workDirectory = context.pluginWorkDirectoryURL
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let stamp = workDirectory.appendingPathComponent("RuleCatalogManifest.validated")

        return [
            .buildCommand(
                displayName: "Validating Rule Catalog Manifest",
                executable: try context.tool(named: "swift-debt-manifest-lint").url,
                arguments: [manifestURL.path, stamp.path],
                inputFiles: [manifestURL],
                outputFiles: [stamp]
            )
        ]
    }
}
