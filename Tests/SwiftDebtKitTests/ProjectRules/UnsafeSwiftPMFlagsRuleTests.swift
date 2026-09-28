import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("UnsafeSwiftPMFlagsRule")
struct UnsafeSwiftPMFlagsRuleTests {
    private func fixtureDirectory(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ProjectRules/UnsafeFlags")
            .appendingPathComponent(name)
    }

    @Test("definition is cataloged as deterministic project scope requiring packageManifest")
    func definitionShape() {
        let definition = UnsafeSwiftPMFlagsRule.definition
        #expect(definition.identity == RuleIdentity("build.swiftpm-unsafe-flags"))
        #expect(definition.scope == .project)
        #expect(definition.mode == .deterministic)
        #expect(definition.requirements.capabilities == [.packageManifest])
    }

    @Test("fires when a target declares unsafeFlags")
    func firesOnUnsafeFlags() throws {
        let directory = fixtureDirectory("WithUnsafeFlags")
        let extractor = PackageManifestExtractor()
        let facts = try extractor.extractFacts(packageDirectory: directory)

        let manifestPath = directory.appendingPathComponent("Package.swift").path
        let detections = UnsafeSwiftPMFlagsRule.detect(manifestPath: manifestPath, facts: facts)

        #expect(detections.count == 1)
        let detection = try #require(detections.first)
        #expect(detection.ruleIdentity == UnsafeSwiftPMFlagsRule.definition.identity)
        #expect(detection.targetName == "WithUnsafeFlags")
        #expect(detection.evidenceLocation.projectManifestPath == manifestPath)
        #expect(detection.evidenceLocation.file == nil)
        #expect(detection.evidenceLocation.line == nil)
    }

    @Test("does not fire when no target declares unsafeFlags")
    func doesNotFireWithoutUnsafeFlags() throws {
        let directory = fixtureDirectory("WithoutUnsafeFlags")
        let extractor = PackageManifestExtractor()
        let facts = try extractor.extractFacts(packageDirectory: directory)

        let manifestPath = directory.appendingPathComponent("Package.swift").path
        let detections = UnsafeSwiftPMFlagsRule.detect(manifestPath: manifestPath, facts: facts)

        #expect(detections.isEmpty)
    }
}
