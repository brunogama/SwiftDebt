import SwiftDebtLifecycle
import Testing

@Suite("R3 relocation-chain CLI acceptance")
struct ScopeRelocationChainCLIWorkflowTests {
    @Test("AT-10 deletion evidence survives an intermediate partial observation")
    func deletionEvidenceSurvivesIntermediatePartialObservation() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.writeFile(relativePath: "Sources/Feature/Input.swift", content: scopeDetectedSource)
        try fixture.writeFile(relativePath: "Sources/Feature/Keep.swift", content: scopeCleanSource)
        try fixture.writeFile(relativePath: "Sources/Elsewhere.swift", content: scopeCleanSource)
        _ = try fixture.commitAll(message: "add observed feature source")
        #expect(try analyzeScope(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(initial.findings.first)

        try fixture.removeFile(relativePath: "Sources/Feature/Input.swift")
        _ = try fixture.commitAll(message: "delete observed feature source")
        let featureDirectory = fixture.repository.appendingPathComponent("Sources/Feature")
        #expect(try analyzeScope(repository: featureDirectory, artifact: fixture.artifact).status == 0)

        try fixture.writeFile(
            relativePath: "Sources/Elsewhere.swift",
            content: "// successor commit\n" + scopeCleanSource
        )
        _ = try fixture.commitAll(message: "advance after partial deletion observation")
        #expect(try analyzeScope(repository: fixture.repository, artifact: fixture.artifact).status == 0)

        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let current = try #require(persisted.finding(id: finding.id))
        #expect(current.lifecycleState == .resolved)
        #expect(current.events.map(\.transition.kind) == [.opened, .unverified, .resolved])
        guard case .resolved(let evidence) = current.events.last?.transition else {
            Issue.record("Expected later repository coverage to resolve")
            return
        }
        #expect(
            evidence.reasons.map(\.code) == [
                "complete-comparable-absence",
                "complete-relocation-coverage",
                "source-deleted",
            ])
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(explanation.standardOutput.contains("source-deleted"))
        #expect(explanation.standardOutput.contains("complete-relocation-coverage"))
        #expect(explanation.standardOutput.contains("Sources/Feature/Input.swift"))
    }

    @Test("FR-22 complete coverage follows relocation across observed Git edges")
    func completeCoverageFollowsMultiEdgeRelocation() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.write(source: scopeDetectedSource)
        try fixture.writeFile(relativePath: "Sources/Other.swift", content: scopeCleanSource)
        _ = try fixture.commitAll(message: "add observed source")
        #expect(try analyzeScope(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(initial.findings.first)

        let manifest = try scopeManifestJSON(
            root: fixture.repository,
            sources: ["Sources/Other.swift"]
        )
        try fixture.writeFile(relativePath: "changed-files.json", content: manifest)
        try fixture.writeFile(relativePath: "Sources/Moved/Input.swift", content: scopeDetectedSource)
        try fixture.removeFile(relativePath: "Sources/Input.swift")
        _ = try fixture.commitAll(message: "move observed source once")
        let manifestURL = fixture.repository.appendingPathComponent("changed-files.json")
        #expect(try analyzeScope(manifest: manifestURL, artifact: fixture.artifact).status == 0)

        try fixture.writeFile(relativePath: "Sources/Final/Input.swift", content: scopeDetectedSource)
        try fixture.removeFile(relativePath: "Sources/Moved/Input.swift")
        _ = try fixture.commitAll(message: "move observed source twice")
        #expect(try analyzeScope(manifest: manifestURL, artifact: fixture.artifact).status == 0)

        try fixture.writeFile(relativePath: "Sources/Final/Input.swift", content: scopeCleanSource)
        _ = try fixture.commitAll(message: "remove debt after relocation")
        #expect(try analyzeScope(repository: fixture.repository, artifact: fixture.artifact).status == 0)

        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let current = try #require(persisted.finding(id: finding.id))
        #expect(current.lifecycleState == .resolved)
        #expect(current.evidenceState == .verifiedAbsent)
        let renames = persisted.snapshots.flatMap(\.provenance.sourceRenames)
        #expect(
            Set(renames.map { "\($0.priorSourcePath.rawValue) -> \($0.currentSourcePath.rawValue)" }) == [
                "Sources/Input.swift -> Sources/Moved/Input.swift",
                "Sources/Moved/Input.swift -> Sources/Final/Input.swift",
            ]
        )
        guard case .resolved(let evidence) = current.events.last?.transition else {
            Issue.record("Expected complete repository coverage to resolve after both relocation edges")
            return
        }
        #expect(evidence.reasons.map(\.code).contains("source-relocated"))
        #expect(evidence.reasons.map(\.code).contains("complete-relocation-coverage"))
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(
            explanation.standardOutput.contains(
                "Sources/Input.swift -> Sources/Moved/Input.swift -> Sources/Final/Input.swift"
            )
        )
    }
}
