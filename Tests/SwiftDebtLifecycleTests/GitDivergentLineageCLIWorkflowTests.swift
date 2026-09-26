import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 divergent Git lineage CLI acceptance")
struct GitDivergentLineageCLIWorkflowTests {
    @Test("AT-21 sibling Git branches retain independent Finding projections")
    func siblingBranchesRemainIndependent() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let orderedArtifact = fixture.directory.appendingPathComponent("ordered-lifecycle.json")
        let reversedArtifact = fixture.directory.appendingPathComponent("reversed-lifecycle.json")
        let rootRevision = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture, artifact: orderedArtifact).status == 0)
        #expect(try analyze(fixture, artifact: reversedArtifact).status == 0)
        let defaultBranch = try fixture.gitOutput(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try fixture.runGit(["checkout", "-b", "feature-a"])
        let branchARevision = try fixture.commit(
            source: Self.absentSource,
            message: "resolve on branch A"
        )
        #expect(try analyze(fixture, artifact: orderedArtifact).status == 0)

        try fixture.runGit(["checkout", defaultBranch])
        try fixture.runGit(["checkout", "-b", "feature-b"])
        let branchBRevision = try fixture.commit(
            source: "// branch B\n" + Self.detectedSource,
            message: "retain debt on branch B"
        )
        #expect(try analyze(fixture, artifact: orderedArtifact).status == 0)
        #expect(try analyze(fixture, artifact: reversedArtifact).status == 0)
        try fixture.runGit(["checkout", "feature-a"])
        #expect(try analyze(fixture, artifact: reversedArtifact).status == 0)

        let artifact = try LifecycleArtifactStore(artifactURL: orderedArtifact).load()
        #expect(artifact.schemaVersion == 2)
        #expect(artifact.snapshots.count == 3)
        #expect(artifact.findings.count == 1)
        #expect(artifact.headSnapshotIDs.count == 2)
        let root = try snapshot(revision: rootRevision, in: artifact)
        let branchA = try snapshot(revision: branchARevision, in: artifact)
        let branchB = try snapshot(revision: branchBRevision, in: artifact)
        #expect(artifact.parentSnapshotID(of: branchA.id) == root.id)
        #expect(artifact.parentSnapshotID(of: branchB.id) == root.id)
        #expect(Set(artifact.headSnapshotIDs) == Set([branchA.id, branchB.id]))

        let finding = try #require(artifact.findings.first)
        let branchAProjection = try #require(
            try artifact.findingProjection(id: finding.id, at: branchA.id)
        )
        let branchBProjection = try #require(
            try artifact.findingProjection(id: finding.id, at: branchB.id)
        )
        #expect(branchAProjection.lifecycleState == .resolved)
        #expect(branchAProjection.evidenceState == .verifiedAbsent)
        #expect(branchAProjection.finding.events.map(\.transition.kind) == [.opened, .resolved])
        #expect(branchBProjection.lifecycleState == .open)
        #expect(branchBProjection.evidenceState == .observed)
        #expect(branchBProjection.finding.events.map(\.transition.kind) == [.opened, .observed])
        #expect(branchAProjection.finding.events.last?.basisEventIDs == [finding.openingEvent.id])
        #expect(branchBProjection.finding.events.last?.basisEventIDs == [finding.openingEvent.id])

        let inventory = try runLifecycleCLI([
            "lifecycle", "inventory", orderedArtifact.path, "--format", "json",
        ])
        #expect(inventory.status == 0, "\(inventory.standardError)")
        let inventoryReport = try JSONDecoder().decode(
            LifecycleInventoryReport.self,
            from: Data(inventory.standardOutput.utf8)
        )
        #expect(inventoryReport.findings.count == 2)
        #expect(Set(inventoryReport.findings.map(\.id)) == [finding.id])
        #expect(Set(inventoryReport.findings.map(\.lifecycleState)) == [.open, .resolved])

        let selectedA = try runLifecycleCLI([
            "lifecycle", "inventory", orderedArtifact.path,
            "--head", branchA.id.rawValue, "--format", "json",
        ])
        let selectedAReport = try JSONDecoder().decode(
            LifecycleInventoryReport.self,
            from: Data(selectedA.standardOutput.utf8)
        )
        #expect(selectedAReport.headSnapshotIDs == [branchA.id])
        #expect(selectedAReport.findings.map(\.lifecycleState) == [.resolved])

        let selectedAExplanation = try runLifecycleCLI([
            "lifecycle", "explain", orderedArtifact.path, finding.id.rawValue,
            "--head", branchA.id.rawValue, "--format", "text",
        ])
        #expect(selectedAExplanation.status == 0, "\(selectedAExplanation.standardError)")
        #expect(selectedAExplanation.standardOutput.contains("Graph head: \(branchA.id.rawValue)"))
        #expect(selectedAExplanation.standardOutput.contains("State: resolved"))
        #expect(!selectedAExplanation.standardOutput.contains(branchB.id.rawValue))

        let selectedAJSON = try runLifecycleCLI([
            "lifecycle", "explain", orderedArtifact.path, finding.id.rawValue,
            "--head", branchA.id.rawValue, "--format", "json",
        ])
        #expect(selectedAJSON.status == 0, "\(selectedAJSON.standardError)")
        let selectedAJSONReport = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(selectedAJSON.standardOutput.utf8)
        )
        #expect(selectedAJSONReport.finding.events.map(\.snapshotID) == [root.id, branchA.id])
        #expect(!selectedAJSON.standardOutput.contains(branchB.id.rawValue))

        let selectedBExplanation = try runLifecycleCLI([
            "lifecycle", "explain", orderedArtifact.path, finding.id.rawValue,
            "--head", branchB.id.rawValue, "--format", "text",
        ])
        #expect(selectedBExplanation.status == 0, "\(selectedBExplanation.standardError)")
        #expect(selectedBExplanation.standardOutput.contains("Graph head: \(branchB.id.rawValue)"))
        #expect(selectedBExplanation.standardOutput.contains("State: open"))
        #expect(!selectedBExplanation.standardOutput.contains(branchA.id.rawValue))

        #expect(try Data(contentsOf: orderedArtifact) == Data(contentsOf: reversedArtifact))
        let bytes = try Data(contentsOf: orderedArtifact)
        #expect(try analyze(fixture, artifact: orderedArtifact).status == 0)
        #expect(try Data(contentsOf: orderedArtifact) == bytes)
    }

    private func analyze(
        _ fixture: TemporaryLifecycleGitRepository,
        artifact: URL
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", artifact.path,
            "--jobs", "2",
        ])
    }

    private func snapshot(
        revision: String,
        in artifact: LifecycleArtifact
    ) throws -> ObservationSnapshot {
        try #require(
            artifact.snapshots.first { snapshot in
                if case .git(let observed, _, _) = snapshot.provenance.sourceIdentity {
                    return observed.rawValue == revision
                }
                return false
            })
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """

    private static let absentSource = """
        func load() throws -> Int { 1 }
        func run() {}
        """
}
