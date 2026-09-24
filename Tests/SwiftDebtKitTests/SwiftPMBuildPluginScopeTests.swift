import Foundation
import Testing

@Suite("SwiftPM build plugin scope")
struct SwiftPMBuildPluginScopeTests {
    @Test func manifestDeclaresEverySupportedApplePlatform() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)

        for declaration in [
            ".macOS(.v13)",
            ".iOS(.v16)",
            ".tvOS(.v16)",
            ".watchOS(.v9)",
            ".visionOS(.v1)",
        ] {
            #expect(manifest.contains(declaration))
        }
    }

    @Test func buildPluginExposesConditionalXcodeProjectPluginAdapter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plugin = root.appendingPathComponent("Plugins/SwiftDebtBuildPlugin/plugin.swift")
        let source = try String(contentsOf: plugin, encoding: .utf8)

        #expect(source.contains("#if canImport(XcodeProjectPlugin)"))
        #expect(source.contains("extension SwiftDebtBuildPlugin: XcodeBuildToolPlugin"))
    }
}
