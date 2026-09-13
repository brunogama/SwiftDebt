import Foundation
import Testing

@Suite("SwiftPM build plugin scope")
struct SwiftPMBuildPluginScopeTests {
    @Test func buildPluginDoesNotExposeXcodeProjectPluginAdapter() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let plugin = root.appendingPathComponent("Plugins/SCMABuildPlugin/plugin.swift")
        let source = try String(contentsOf: plugin, encoding: .utf8)

        #expect(!source.contains("XcodeProjectPlugin"))
    }
}
