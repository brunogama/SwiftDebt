import SwiftDebtLifecycle
import Testing

@Suite("R3 new Finding validation through the real CLI")
struct LifecycleOpeningValidationCLIWorkflowTests {
    @Test("An unchanged Detection continues while a second Detection in the same source opens")
    func continuationAndNewFindingInOneSource() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.originalSource, message: "add forced try")
        let initial = try analyze(fixture)
        #expect(initial.status == 0, "\(initial.standardError)")
        let firstArtifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let firstFinding = try #require(firstArtifact.findings.first)

        _ = try fixture.commit(source: Self.expandedSource, message: "add another forced try")
        let incremental = try analyze(fixture)
        try #require(incremental.status == 0, "\(incremental.standardError)")
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(artifact.snapshots.count == 2)
        #expect(artifact.findings.count == 2)
        #expect(artifact.unresolvedDetections.isEmpty)
        let continued = try #require(artifact.findings.first { $0.id == firstFinding.id })
        #expect(continued.events.map(\.transition.kind) == [.opened, .observed])
        let newFinding = try #require(artifact.findings.first { $0.id != firstFinding.id })
        #expect(newFinding.events.map(\.transition.kind) == [.opened])
        #expect(newFinding.firstObservationSnapshotID == artifact.snapshots[1].id)
    }

    private func analyze(_ fixture: TemporaryLifecycleGitRepository) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--jobs", "1",
            "--lifecycle-artifact", fixture.artifact.path,
        ])
    }

    private static let originalSource = """
        func load() throws -> Int { 1 }
        func first() { _ = try! load() }
        """

    private static let expandedSource = """
        func load() throws -> Int { 1 }
        func first() { _ = try! load() }
        func fetch() throws -> Int { 2 }
        func second() { _ = try! fetch() }
        """
}
