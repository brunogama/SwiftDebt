import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 divergent Git lineage CLI acceptance")
struct GitDivergentLineageCLIWorkflowTests {
    @Test("AT-21 sibling Git branches retain independent histories")
    func siblingBranchesRemainIndependent() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture).status == 0)
        let defaultBranch = try fixture.gitOutput(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try fixture.runGit(["checkout", "-b", "feature-a"])
        let branchARevision = try fixture.commit(
            source: "// branch A\n" + Self.detectedSource,
            message: "change branch A"
        )
        #expect(try analyze(fixture).status == 0)
        let branchASnapshot = try #require(
            LifecycleArtifactStore(artifactURL: fixture.artifact).load().snapshots.first {
                if case .git(let revision, _, _) = $0.provenance.sourceIdentity {
                    return revision.rawValue == branchARevision
                }
                return false
            }
        )

        try fixture.runGit(["checkout", defaultBranch])
        try fixture.runGit(["checkout", "-b", "feature-b"])
        let branchBRevision = try fixture.commit(
            source: "// branch B\n" + Self.detectedSource,
            message: "change branch B"
        )
        let branchBResult = try analyze(fixture)
        #expect(branchBResult.status == 0, "\(branchBResult.standardError)")
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(artifact.snapshots.count == 3)
        #expect(artifact.lineageHeads.count == 2)
        let branchBSnapshot = try #require(
            artifact.snapshots.first {
                if case .git(let revision, _, _) = $0.provenance.sourceIdentity {
                    return revision.rawValue == branchBRevision
                }
                return false
            })
        #expect(branchASnapshot.provenance.lineage.lineageID != branchBSnapshot.provenance.lineage.lineageID)
        #expect(artifact.findings.allSatisfy { $0.lifecycleState == .open })

        let bytes = try Data(contentsOf: fixture.artifact)
        try fixture.runGit(["checkout", "feature-a"])
        #expect(try analyze(fixture).status == 0)
        #expect(try Data(contentsOf: fixture.artifact) == bytes)
    }

    private func analyze(_ fixture: TemporaryLifecycleGitRepository) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
            "--jobs", "2",
        ])
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """
}
