import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 Git introduction CLI acceptance")
struct IntroductionCLIWorkflowTests {
    @Test("AT-16 verified parent absence proves the exact child introduction")
    func exactLinearIntroduction() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let parentRevision = try fixture.commit(
            source: Self.absentSource,
            message: "add clean implementation"
        )
        let childRevision = try fixture.commit(
            source: Self.detectedSource,
            message: "introduce forced try"
        )
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)

        let inference = try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 8)

        #expect(inference.status == 0)
        #expect(inference.standardError.isEmpty)
        #expect(inference.standardOutput.contains("Introduction: exact \(childRevision)"))
        #expect(inference.standardOutput.contains("verified-parent-absence"))
        #expect(inference.standardOutput.contains(parentRevision))
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(explanation.standardOutput.contains("Introduction: exact \(childRevision)"))
        #expect(explanation.standardOutput.contains("History budget: 8 revisions"))
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let conclusion = try #require(persisted.currentIntroductionConclusion(for: finding.id))
        #expect(conclusion.kind == .exact)
        #expect(conclusion.evidence.boundary.maximumRevisions == 8)
        #expect(conclusion.evidence.revisions.map(\.revision.rawValue) == [childRevision, parentRevision])
        let childEvidence = try #require(conclusion.evidence.revisions.first)
        #expect(childEvidence.parentRevisions.map(\.rawValue) == [parentRevision])
        #expect(childEvidence.observation?.provenance.scope == .repository)
        let jsonExplanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.artifact.path, finding.id.rawValue,
            "--format", "json",
        ])
        let json = try #require(
            try JSONSerialization.jsonObject(with: Data(jsonExplanation.standardOutput.utf8))
                as? [String: Any]
        )
        let jsonConclusions = try #require(json["introductionConclusions"] as? [[String: Any]])
        #expect(jsonConclusions.first?["kind"] as? String == "exact")
        #expect(jsonConclusions.first?["exactRevision"] as? String == childRevision)
    }

    @Test("AT-17 an unparseable parent bounds introduction")
    func unparseableParentBoundsIntroduction() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.unparseableSource, message: "add incomplete source")
        let childRevision = try fixture.commit(source: Self.detectedSource, message: "repair with forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)

        let inference = try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 8)

        #expect(inference.status == 0)
        #expect(inference.standardOutput.contains("Introduction: bounded earliest-positive=\(childRevision)"))
        #expect(inference.standardOutput.contains("historical-observation-incomplete"))
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(persisted.currentIntroductionConclusion(for: finding.id)?.kind == .bounded)
        #expect(persisted.currentIntroductionConclusion(for: finding.id)?.exactRevision == nil)
    }

    @Test("AT-18 a merge follows its one positive parent")
    func mergeFollowsPositiveParent() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let rootRevision = try fixture.commit(source: Self.absentSource, message: "add clean implementation")
        try fixture.runGit(["checkout", "-b", "positive-history"])
        let positiveRevision = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        try fixture.runGit(["checkout", "-b", "clean-history", rootRevision])
        try fixture.runGit(["commit", "--allow-empty", "-m", "clean side history"])
        try fixture.runGit(["checkout", "positive-history"])
        try fixture.runGit(["merge", "--no-ff", "clean-history", "-m", "merge clean history"])
        let mergeRevision = try fixture.gitOutput(["rev-parse", "HEAD"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)

        let inference = try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 16)

        #expect(inference.status == 0)
        #expect(inference.standardOutput.contains("Introduction: exact \(positiveRevision)"))
        #expect(!inference.standardOutput.contains("Introduction: exact \(mergeRevision)"))
        #expect(inference.standardOutput.contains("positive-parent-followed"))
    }

    @Test("AT-19 a merge is exact when every parent proves absence")
    func mergeIntroducesFindingAfterParentAbsence() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let rootRevision = try fixture.commit(source: Self.absentSource, message: "add clean implementation")
        try fixture.runGit(["checkout", "-b", "side-history"])
        try fixture.writeFile(relativePath: "Sources/Side.swift", content: "func sideMarker() {}\n")
        _ = try fixture.commitAll(message: "add side marker")
        try fixture.runGit(["checkout", "-b", "main-history", rootRevision])
        try fixture.writeFile(relativePath: "Sources/Main.swift", content: "func mainMarker() {}\n")
        _ = try fixture.commitAll(message: "add main marker")
        try fixture.runGit(["merge", "--no-ff", "--no-commit", "side-history"])
        try fixture.write(source: Self.detectedSource)
        let mergeRevision = try fixture.commitAll(message: "introduce forced try in merge")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)

        let inference = try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 16)

        #expect(inference.status == 0)
        #expect(inference.standardOutput.contains("Introduction: exact \(mergeRevision)"))
        #expect(inference.standardOutput.contains("verified-parent-absence"))
    }

    @Test("AT-20 a dirty worktree blocks an exact committed introduction")
    func dirtyWorktreeBlocksExactIntroduction() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.absentSource, message: "add clean implementation")
        let childRevision = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(original.findings.first)
        try fixture.writeFile(relativePath: "notes.txt", content: "uncommitted\n")

        let inference = try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 8)

        #expect(inference.status == 0)
        #expect(inference.standardOutput.contains("Introduction: bounded earliest-positive=\(childRevision)"))
        #expect(inference.standardOutput.contains("dirty-working-tree"))
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(persisted.finding(id: finding.id)?.firstObservationSnapshotID == finding.firstObservationSnapshotID)
    }

    @Test("AT-20 a shallow clone blocks an exact committed introduction")
    func shallowCloneBlocksExactIntroduction() throws {
        let origin = try TemporaryLifecycleGitRepository()
        _ = try origin.commit(source: Self.absentSource, message: "add clean implementation")
        let childRevision = try origin.commit(source: Self.detectedSource, message: "introduce forced try")
        let clone = origin.directory.appendingPathComponent("shallow-clone", isDirectory: true)
        let cloneResult = try runLifecycleProcess(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "clone", "--depth", "1", origin.repository.absoluteString, clone.path],
            directory: origin.directory,
            mergeStandardError: true
        )
        #expect(cloneResult.status == 0)
        let artifactURL = clone.appendingPathComponent(".swift-debt/lifecycle.json")
        #expect(try analyze(repository: clone, artifact: artifactURL).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: artifactURL).load()
        let finding = try #require(original.findings.first)

        let inference = try inferIntroduction(
            finding.id,
            repository: clone,
            artifact: artifactURL,
            maximumRevisions: 8
        )

        #expect(inference.status == 0)
        #expect(inference.standardOutput.contains("Introduction: bounded earliest-positive=\(childRevision)"))
        #expect(inference.standardOutput.contains("shallow-history"))
        let persisted = try LifecycleArtifactStore(artifactURL: artifactURL).load()
        #expect(persisted.finding(id: finding.id)?.firstObservationSnapshotID == finding.firstObservationSnapshotID)
    }

    @Test("A disconnected repository cannot supply introduction ancestry")
    func disconnectedRepositoryIsUnavailable() throws {
        let recorded = try TemporaryLifecycleGitRepository()
        _ = try recorded.commit(source: Self.absentSource, message: "add clean implementation")
        _ = try recorded.commit(source: Self.detectedSource, message: "introduce forced try")
        #expect(try analyzeLifecycle(recorded).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: recorded.artifact).load()
        let finding = try #require(original.findings.first)
        let disconnected = try TemporaryLifecycleGitRepository()
        _ = try disconnected.commit(source: Self.detectedSource, message: "unrelated forced try")

        let inference = try inferIntroduction(
            finding.id,
            repository: disconnected.repository,
            artifact: recorded.artifact,
            maximumRevisions: 8
        )

        #expect(inference.status == 0)
        #expect(inference.standardOutput.contains("Introduction: unavailable"))
        #expect(inference.standardOutput.contains("history-ancestry-unavailable"))
        let persisted = try LifecycleArtifactStore(artifactURL: recorded.artifact).load()
        #expect(persisted.finding(id: finding.id)?.firstObservationSnapshotID == finding.firstObservationSnapshotID)
    }

    @Test("A deeper bounded query appends an exact refinement and retries byte-identically")
    func deeperQueryRefinesWithoutRewritingFacts() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.absentSource, message: "add clean implementation")
        let introducedRevision = try fixture.commit(
            source: Self.detectedSource,
            message: "introduce forced try"
        )
        _ = try fixture.commit(source: Self.shiftedDetectedSource, message: "move forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(original.findings.first)

        let bounded = try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 1)
        #expect(bounded.standardOutput.contains("Introduction: bounded"))
        #expect(bounded.standardOutput.contains("history-budget-exhausted"))
        let exact = try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 8)
        #expect(exact.standardOutput.contains("Introduction: exact \(introducedRevision)"))
        let refined = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(refined.introductionConclusions(for: finding.id).map(\.kind) == [.bounded, .exact])
        #expect(refined.finding(id: finding.id)?.firstObservationSnapshotID == finding.firstObservationSnapshotID)

        let exactBytes = try Data(contentsOf: fixture.artifact)
        #expect(try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 8).status == 0)
        #expect(try Data(contentsOf: fixture.artifact) == exactBytes)
    }

    @Test("A tampered exact Introduction Conclusion fails closed")
    func tamperedExactConclusionIsRejected() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let parentRevision = try fixture.commit(source: Self.absentSource, message: "add clean implementation")
        _ = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)
        #expect(try inferIntroduction(finding.id, fixture: fixture, maximumRevisions: 8).status == 0)

        var root = try artifactJSONObject(at: fixture.artifact)
        var conclusions = try #require(root["introductionConclusions"] as? [[String: Any]])
        var conclusion = try #require(conclusions.first)
        conclusion["exactRevision"] = parentRevision
        conclusions[0] = conclusion
        root["introductionConclusions"] = conclusions
        try lifecycleJSONData(root).write(to: fixture.artifact, options: .atomic)

        #expect(throws: LifecycleStoreError.self) {
            try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        }
    }

    private func inferIntroduction(
        _ findingID: FindingID,
        fixture: TemporaryLifecycleGitRepository,
        maximumRevisions: Int
    ) throws -> LifecycleCLIRunResult {
        try inferIntroduction(
            findingID,
            repository: fixture.repository,
            artifact: fixture.artifact,
            maximumRevisions: maximumRevisions
        )
    }

    private func inferIntroduction(
        _ findingID: FindingID,
        repository: URL,
        artifact: URL,
        maximumRevisions: Int
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "lifecycle", "infer-introduction",
            artifact.path,
            findingID.rawValue,
            "--repository", repository.path,
            "--max-revisions", String(maximumRevisions),
        ])
    }

    private func analyze(repository: URL, artifact: URL) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", repository.path,
            "--format", "json",
            "--lifecycle-artifact", artifact.path,
            "--jobs", "2",
        ])
    }

    private static let absentSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try? load() }
        """

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """

    private static let shiftedDetectedSource = """
        func load() throws -> Int { 1 }

        // The structural subject remains the same after a source move.
        func run() { _ = try! load() }
        """

    private static let unparseableSource = """
        func load( {
        """
}
