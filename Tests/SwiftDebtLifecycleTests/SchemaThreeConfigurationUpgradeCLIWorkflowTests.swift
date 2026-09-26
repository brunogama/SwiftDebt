import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 configuration declaration upgrade CLI acceptance")
struct SchemaThreeConfigurationUpgradeCLIWorkflowTests {
    @Test("Adding a configuration declaration preserves same-revision continuity")
    func declarationUpgradePreservesContinuity() throws {
        let source = try #require(
            Bundle.module.url(
                forResource: "SchemaThreeBeforeConfigurationDeclarations",
                withExtension: "json"
            )
        )
        let fixture = try TemporaryLifecycleGitRepository()
        let artifactURL = fixture.directory.appendingPathComponent("before-upgrade.json")
        let detectedSource = "func load() throws -> Int { 1 }\nfunc run() { _ = try! load() }\n"
        let shiftedSource = "func load() throws -> Int { 1 }\n// shifted location\nfunc run() { _ = try! load() }\n"
        let openingRevision = try fixture.commit(
            source: detectedSource, message: "add force try", date: "2026-02-01T00:00:00 +0000")
        #expect(openingRevision == "70fdc68fee429ca249722dc0b86abcb0c56a62a0")
        try FileManager.default.copyItem(at: source, to: artifactURL)
        let opening = try LifecycleArtifactStore(artifactURL: artifactURL).load()
        let findingID = try #require(opening.findings.first?.id)
        #expect(opening.findings.first?.events.map(\.transition.kind) == [.opened])

        _ = try fixture.commit(
            source: shiftedSource, message: "shift force try", date: "2026-02-02T00:00:00 +0000")
        let result = try runLifecycleCLI([
            "analyze", fixture.repository.path, "--format", "json",
            "--lifecycle-artifact", artifactURL.path, "--jobs", "2",
        ])
        #expect(result.status == 0)
        let continued = try LifecycleArtifactStore(artifactURL: artifactURL).load()
        let finding = try #require(continued.finding(id: findingID))
        #expect(continued.findings.count == 1)
        #expect(continued.unresolvedDetections.isEmpty)
        #expect(finding.events.map(\.transition.kind) == [.opened, .observed])
        #expect(finding.events.last?.semanticComparisons.first?.decision == .compatible)
        #expect(continued.snapshots.last?.detections.first?.location.line == 3)
    }
}
