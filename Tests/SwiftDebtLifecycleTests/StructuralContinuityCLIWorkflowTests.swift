import SwiftDebtLifecycle
import Testing

@Suite("R3 structural continuity CLI acceptance")
struct StructuralContinuityCLIWorkflowTests {
    @Test("AT-4 a uniquely anchored Git rename preserves the Finding")
    func gitRenamePreservesFinding() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.forcedTrySource, message: "add forced try")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let originalFinding = try #require(initial.findings.first)

        try fixture.runGit(["mv", "Sources/Input.swift", "Sources/Renamed.swift"])
        _ = try fixture.commitAll(message: "rename source")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let moved = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(moved.findings.first)
        let successor = try #require(moved.snapshots.first { $0.provenance.lineage.sequence == 2 })

        #expect(moved.findings.count == 1)
        #expect(moved.unresolvedDetections.isEmpty)
        #expect(finding.id == originalFinding.id)
        #expect(finding.events.map(\.transition.kind) == [.opened, .observed])
        #expect(successor.provenance.sourceRenames.count == 1)
        #expect(successor.provenance.sourceRenames.first?.priorSourcePath.rawValue == "Sources/Input.swift")
        #expect(successor.provenance.sourceRenames.first?.currentSourcePath.rawValue == "Sources/Renamed.swift")
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("structural-anchor-match"))
        #expect(explanation.standardOutput.contains("git-source-rename"))
    }

    @Test("An identical cross-file anchor without a Git rename stays unresolved")
    func uncorroboratedCrossFileMatchStaysUnresolved() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.largeSource(marker: "original"), message: "add original")
        #expect(try analyzeLifecycle(fixture).status == 0)

        try fixture.removeFile(relativePath: "Sources/Input.swift")
        try fixture.writeFile(
            relativePath: "Sources/Replacement.swift",
            content: Self.largeSource(marker: "replacement")
        )
        _ = try fixture.commitAll(message: "replace file without rename evidence")
        let detectedRenames = try fixture.gitOutput([
            "diff", "--name-status", "--find-renames", "--diff-filter=R", "HEAD^", "HEAD", "--",
        ])
        #expect(detectedRenames.isEmpty)

        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)
        let unresolved = try #require(artifact.unresolvedDetections.first)

        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 1)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .continuityAmbiguous)
        #expect(unresolved.candidateFindingIDs == [finding.id])
        #expect(unresolved.reasons.map(\.code).contains("cross-file-move-uncorroborated"))
    }

    @Test("AT-5 copying one anchored declaration to two files stays ambiguous")
    func copiedDeclarationStaysAmbiguous() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.forcedTrySource, message: "add original")
        #expect(try analyzeLifecycle(fixture).status == 0)

        try fixture.writeFile(relativePath: "Sources/Copy.swift", content: Self.forcedTrySource)
        _ = try fixture.commitAll(message: "copy declaration")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)

        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 2)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .continuityAmbiguous)
        #expect(finding.events.map(\.transition.kind) == [.opened, .continuityAmbiguous])
        #expect(
            artifact.unresolvedDetections.allSatisfy {
                $0.candidateFindingIDs == [finding.id]
            })
        let reasonCodes = Set(artifact.unresolvedDetections.flatMap { $0.reasons.map(\.code) })
        #expect(reasonCodes.contains("structural-assignment-not-unique"))
        #expect(reasonCodes.contains("cross-file-move-uncorroborated"))
    }

    @Test("AT-6 two anchored Findings collapsing to one Detection stay ambiguous")
    func collapsedDeclarationsStayAmbiguous() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.writeFile(relativePath: "Sources/Input.swift", content: Self.forcedTrySource)
        try fixture.writeFile(relativePath: "Sources/Copy.swift", content: Self.forcedTrySource)
        _ = try fixture.commitAll(message: "add duplicate declarations")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(initial.findings.count == 2)

        try fixture.removeFile(relativePath: "Sources/Copy.swift")
        _ = try fixture.commitAll(message: "collapse duplicate declarations")
        #expect(try analyzeLifecycle(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let unresolved = try #require(artifact.unresolvedDetections.first)

        #expect(artifact.findings.count == 2)
        #expect(artifact.unresolvedDetections.count == 1)
        #expect(artifact.findings.allSatisfy { $0.lifecycleState == .open })
        #expect(artifact.findings.allSatisfy { $0.evidenceState == .continuityAmbiguous })
        #expect(unresolved.candidateFindingIDs == artifact.findings.map(\.id))
        #expect(unresolved.reasons.map(\.code).contains("structural-assignment-not-unique"))
    }

    private static let forcedTrySource = """
        func load() throws -> Int { 1 }
        func run() {
            _ = try! load()
        }
        """

    private static func largeSource(marker: String) -> String {
        let unrelatedLines = (0..<80).map { "let \(marker)\($0) = \($0)" }
        return
            (unrelatedLines + [
                "func load() throws -> Int { 1 }",
                "func run() {",
                "    _ = try! load()",
                "}",
            ]).joined(separator: "\n")
    }
}
