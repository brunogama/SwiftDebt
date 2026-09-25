import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import Testing

@Suite("R3 scope boundary CLI acceptance")
struct ScopeRelocationBoundaryCLIWorkflowTests {
    @Test("AT-9 a changed-files manifest leaves the prior SourceUnit unverified")
    func changedFilesManifestLeavesPriorSourceUnverified() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.write(source: scopeDetectedSource)
        try fixture.writeFile(relativePath: "Sources/Other.swift", content: scopeCleanSource)
        _ = try fixture.commitAll(message: "add observed and clean sources")
        #expect(try analyzeScope(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(initial.findings.first)

        try fixture.writeFile(
            relativePath: "Sources/Other.swift",
            content: "// changed file\n" + scopeCleanSource
        )
        let manifest = try scopeManifestJSON(
            root: fixture.repository,
            sources: ["Sources/Other.swift"]
        )
        try fixture.writeFile(relativePath: "changed-files.json", content: manifest)
        _ = try fixture.commitAll(message: "analyze one changed source")

        let result = try analyzeScope(
            manifest: fixture.repository.appendingPathComponent("changed-files.json"),
            artifact: fixture.artifact)
        #expect(result.status == 0)
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let current = try #require(persisted.finding(id: finding.id))
        #expect(current.lifecycleState == .open)
        #expect(current.evidenceState == .unverified)
        let latest = try #require(latestScopeSnapshot(in: persisted))
        let selection = try #require(latest.provenance.sourceSelection)
        #expect(selection.kind == .manifest)
        #expect(selection.repositoryRelativeRoot == nil)
        #expect(latest.sources.map(\.sourcePath.rawValue) == ["Sources/Other.swift"])
        guard case .unverified(let reasons) = current.events.last?.transition else {
            Issue.record("Expected changed-files coverage to remain unverified")
            return
        }
        #expect(reasons.map(\.code).contains("prior-source-out-of-scope"))
        #expect(reasons.map(\.code).contains("relocation-coverage-incomplete"))
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(explanation.standardOutput.contains("prior-source-out-of-scope"))
        #expect(explanation.standardOutput.contains("Sources/Input.swift"))
    }

    @Test("AT-10 deleting the sole Swift SourceUnit can resolve")
    func deletingSoleSourceCanResolve() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.write(source: scopeDetectedSource)
        _ = try fixture.commitAll(message: "add sole observed source")
        #expect(try analyzeScope(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(initial.findings.first)

        try fixture.removeFile(relativePath: "Sources/Input.swift")
        _ = try fixture.commitAll(message: "delete sole observed source")
        let result = try analyzeScope(repository: fixture.repository, artifact: fixture.artifact)
        #expect(result.status == 0)
        let report = try JSONDecoder().decode(
            AnalysisReport.self,
            from: Data(result.standardOutput.utf8)
        )
        #expect(report.schemaVersion == 2)
        #expect(report.complete)
        #expect(report.inputFileCount == 0)
        #expect(report.inputFiles.isEmpty)

        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let current = try #require(persisted.finding(id: finding.id))
        #expect(current.lifecycleState == .resolved)
        #expect(current.evidenceState == .verifiedAbsent)
        let latest = try #require(latestScopeSnapshot(in: persisted))
        #expect(latest.sources.isEmpty)
        #expect(latest.atomicObservations.isEmpty)
        #expect(!latest.rules.isEmpty)
        #expect(
            latest.provenance.sourceDeletions.map(\.priorSourcePath.rawValue) == [
                "Sources/Input.swift"
            ])
        guard case .resolved(let evidence) = current.events.last?.transition else {
            Issue.record("Expected sole-source deletion to resolve")
            return
        }
        #expect(evidence.coveredAtomicObservationIDs.isEmpty)
        #expect(
            evidence.reasons.map(\.code) == [
                "complete-comparable-absence",
                "complete-relocation-coverage",
                "source-deleted",
            ])

        var root = try artifactJSONObject(at: fixture.artifact)
        var snapshots = try #require(root["snapshots"] as? [[String: Any]])
        let latestIndex = try #require(snapshots.firstIndex { $0["id"] as? String == latest.id.rawValue })
        snapshots[latestIndex]["rules"] = []
        root["snapshots"] = snapshots
        try lifecycleJSONData(root).write(to: fixture.artifact, options: .atomic)
        #expect(throws: LifecycleStoreError.self) {
            try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        }
    }

}
