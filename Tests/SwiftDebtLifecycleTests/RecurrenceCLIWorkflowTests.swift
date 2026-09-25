import SwiftDebtLifecycle
import Testing

@Suite("R3 recurrence CLI acceptance")
struct RecurrenceCLIWorkflowTests {
    @Test("AT-14 a unique structural match reopens after verified resolution")
    func uniqueMatchReopensFinding() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.originalSource, message: "add forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let opened = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let originalID = try #require(opened.findings.first?.id)

        _ = try fixture.commit(source: Self.resolvedSource, message: "resolve forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let resolved = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(resolved.finding(id: originalID)?.lifecycleState == .resolved)

        _ = try fixture.commit(source: Self.originalSource, message: "restore forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let reopened = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(reopened.finding(id: originalID))

        #expect(reopened.findings.count == 1)
        #expect(reopened.unresolvedDetections.isEmpty)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .observed)
        #expect(finding.events.map(\.transition.kind) == [.opened, .resolved, .reopened])
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(explanation.standardOutput.contains("reopened"))
        #expect(explanation.standardOutput.contains("structural-anchor-match"))
    }

    @Test("AT-15 a structurally distinct occurrence in another file opens a new Finding")
    func unrelatedCrossFileOccurrenceOpensNewFinding() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.originalSource, message: "add original forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let opened = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let oldFinding = try #require(opened.findings.first)
        let oldDetection = try #require(opened.snapshots.first?.detections.first)

        _ = try fixture.commit(source: Self.resolvedSource, message: "resolve original")
        #expect(try analyzeLifecycle(fixture).status == 0)
        try fixture.writeFile(
            relativePath: "Sources/Unrelated.swift",
            content: Self.unrelatedCrossFileSource
        )
        _ = try fixture.commitAll(message: "add unrelated forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let retained = try #require(artifact.finding(id: oldFinding.id))
        let newFinding = try #require(artifact.findings.first { $0.id != oldFinding.id })
        let newestSnapshot = try #require(artifact.snapshots.first { $0.provenance.lineage.sequence == 3 })
        let replacementDetection = try #require(newestSnapshot.detections.first)

        #expect(artifact.findings.count == 2)
        #expect(artifact.unresolvedDetections.isEmpty)
        #expect(retained.lifecycleState == .resolved)
        #expect(retained.events.map(\.transition.kind) == [.opened, .resolved])
        #expect(newFinding.lifecycleState == .open)
        #expect(newFinding.events.map(\.transition.kind) == [.opened])
        #expect(oldDetection.location.sourcePath != replacementDetection.location.sourcePath)
        #expect(oldDetection.structuralEvidence != replacementDetection.structuralEvidence)
        #expect(newestSnapshot.provenance.sourceRenames.isEmpty)
    }

    @Test("AT-27 same-location structural divergence stays unresolved")
    func unrelatedReplacementAtSameLocationStaysUnresolved() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.originalSource, message: "add original forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let opened = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let oldFinding = try #require(opened.findings.first)
        let oldDetection = try #require(opened.snapshots.first?.detections.first)

        _ = try fixture.commit(source: Self.resolvedSource, message: "resolve original")
        #expect(try analyzeLifecycle(fixture).status == 0)
        _ = try fixture.commit(source: Self.unrelatedReplacementSource, message: "replace occurrence")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let retained = try #require(artifact.finding(id: oldFinding.id))
        let unresolved = try #require(artifact.unresolvedDetections.first)
        let newestSnapshot = try #require(artifact.snapshots.first { $0.provenance.lineage.sequence == 3 })
        let replacementDetection = try #require(newestSnapshot.detections.first)

        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 1)
        #expect(retained.lifecycleState == .resolved)
        #expect(retained.evidenceState == .verifiedAbsent)
        #expect(retained.events.map(\.transition.kind) == [.opened, .resolved])
        #expect(unresolved.candidateFindingIDs == [oldFinding.id])
        #expect(unresolved.reasons.map(\.code) == ["same-source-structural-divergence"])
        #expect(oldDetection.location == replacementDetection.location)
        #expect(oldDetection.structuralEvidence != replacementDetection.structuralEvidence)
    }

    @Test("An edited subject in the same declaration remains unresolved")
    func editedSubjectDoesNotFabricateDiscontinuity() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.originalSource, message: "add original forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)

        _ = try fixture.commit(source: Self.editedSubjectSource, message: "edit forced expression")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)
        let unresolved = try #require(artifact.unresolvedDetections.first)

        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 1)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .continuityAmbiguous)
        #expect(finding.events.map(\.transition.kind) == [.opened, .continuityAmbiguous])
        #expect(unresolved.reasons.map(\.code).contains("subject-changed-within-declaration"))
    }

    private static let originalSource = """
        func load() throws -> Int { 1 }
        func replacement() throws -> Int { 2 }
        func run() { _ = try! load() }
        """

    private static let resolvedSource = """
        func load() throws -> Int { 1 }
        func replacement() throws -> Int { 2 }
        func run() { _ = try? load() }
        """

    private static let editedSubjectSource = """
        func load() throws -> Int { 1 }
        func replacement() throws -> Int { 2 }
        func run() { _ = try! replacement() }
        """

    private static let unrelatedReplacementSource = """
        func load() throws -> Int { 1 }
        func replacement() throws -> Int { 2 }
        func new() { _ = try! replacement() }
        """

    private static let unrelatedCrossFileSource = """
        func fetch() throws -> String { "value" }
        func consume() { _ = try! fetch() }
        """
}
