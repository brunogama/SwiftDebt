import Foundation
import SCMACore
import Testing

@testable import SCMAKit

@Suite("Filesystem and integration boundaries")
struct WorkspaceTests {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scma-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ text: String, name: String, root: URL) throws {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
    @Test func discoveryRespectsExclusionsAndIgnoresBuildDirectories() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("class C {}", name: "Sources/Space Name.swift", root: root)
        try write("class Bad {", name: "Generated/Bad.swift", root: root)
        try write("class Bad {", name: ".build/Bad.swift", root: root)
        try write("not valid Swift", name: "Package.swift", root: root)
        let result = try await AnalysisService().run(.init(path: root.path, format: .json, exclude: ["Generated"]))
        #expect(result.exitStatus == 0)
        #expect(result.report.inputFiles == ["Sources/Space Name.swift"])
    }
    @Test func configurationGateControlsExitStatus() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("class C { func f() { if true {} } }", name: "C.swift", root: root)
        try write("{\"thresholds\":{\"CCF\":1},\"failOnViolation\":true}", name: ".scma.json", root: root)
        let result = try await AnalysisService().run(.init(path: root.path))
        #expect(result.exitStatus == 1)
        #expect(result.report.findings.count == 1)
    }
    @Test func missingExplicitConfigurationFails() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("class C {}", name: "C.swift", root: root)
        await #expect(throws: (any Error).self) {
            try await AnalysisService().run(
                .init(path: root.path, configurationPath: root.appendingPathComponent("missing.json").path))
        }
    }
    @Test func reportsNeverOverwriteSwiftInput() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let code = "class C {}"
        try write(code, name: "C.swift", root: root)
        await #expect(throws: (any Error).self) {
            try await AnalysisService().run(
                .init(path: root.path, outputPath: root.appendingPathComponent("C.swift").path))
        }
        #expect(try String(contentsOf: root.appendingPathComponent("C.swift"), encoding: .utf8) == code)
    }
    @Test func outputAndStampAreWrittenAfterSuccessfulAnalysis() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("class C {}", name: "Sources/C.swift", root: root)
        let output = root.appendingPathComponent("reports/report.json")
        let stamp = root.appendingPathComponent(".build/plugin/SCMA.analysis.swift")
        let result = try await AnalysisService().run(
            .init(path: root.path, outputPath: output.path, stampPath: stamp.path, format: .json))
        #expect(result.standardOutput.isEmpty)
        #expect(FileManager.default.fileExists(atPath: output.path))
        #expect(FileManager.default.fileExists(atPath: stamp.path))
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(object["overallScore"] is NSNull)
    }
    @Test func failedGateDoesNotWriteStamp() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("class C { func f() {} }", name: "C.swift", root: root)
        let stamp = root.appendingPathComponent(".build/SCMA.analysis.swift")
        let result = try await AnalysisService().run(
            .init(path: root.path, stampPath: stamp.path, failOnViolation: true, thresholds: [.ccf: 0]))
        #expect(result.exitStatus == 1)
        #expect(!FileManager.default.fileExists(atPath: stamp.path))
    }
    @Test func explicitManifestRejectsFilesOutsideRoot() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = SourceManifest(root: root.path, sources: [.init(path: "../escape.swift", module: "Bad")])
        let path = root.appendingPathComponent("manifest.json")
        try JSONEncoder().encode(manifest).write(to: path)
        await #expect(throws: (any Error).self) { try await AnalysisService().run(.init(manifestPath: path.path)) }
    }
    @Test func invalidUTF8IsRejected() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0xFF, 0xFE, 0xFD]).write(to: root.appendingPathComponent("Bad.swift"))
        await #expect(throws: (any Error).self) { try await AnalysisService().run(.init(path: root.path)) }
    }
}
