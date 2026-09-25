import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 scope and relocation CLI acceptance")
struct ScopeRelocationCLIWorkflowTests {
    @Test("AT-9 an explicitly excluded prior SourceUnit stays unverified")
    func excludedPriorSourceStaysUnverified() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.write(source: Self.detectedSource)
        try fixture.writeFile(relativePath: "Sources/Other.swift", content: Self.cleanSource)
        _ = try fixture.commitAll(message: "add observed and clean sources")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(initial.findings.first)

        try fixture.writeFile(
            relativePath: "Sources/Other.swift",
            content: "// changed file\n" + Self.cleanSource
        )
        _ = try fixture.commitAll(message: "change only the clean source")
        let scoped = try analyze(
            repository: fixture.repository,
            artifact: fixture.artifact,
            exclusions: ["Sources/Input.swift"]
        )

        #expect(scoped.status == 0)
        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let current = try #require(persisted.finding(id: finding.id))
        #expect(current.lifecycleState == .open)
        #expect(current.evidenceState == .unverified)
        let latestSnapshot = try #require(Self.latestSnapshot(in: persisted))
        let selection = try #require(latestSnapshot.provenance.sourceSelection)
        #expect(selection.kind == .directory)
        #expect(selection.repositoryRelativeRoot == nil)
        #expect(selection.excludedPathPrefixes.map(\.rawValue) == ["Sources/Input.swift"])
        guard case .unverified(let reasons) = current.events.last?.transition else {
            Issue.record("Expected excluded prior source to record unverified evidence")
            return
        }
        #expect(reasons.map(\.code).contains("prior-source-out-of-scope"))
        #expect(reasons.map(\.code).contains("relocation-coverage-incomplete"))
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(explanation.standardOutput.contains("prior-source-out-of-scope"))
        #expect(explanation.standardOutput.contains("Sources/Input.swift"))
        #expect(!explanation.standardOutput.contains(" resolved\n"))
    }

    @Test("AT-10 repository coverage resolves a Git-deleted SourceUnit")
    func repositoryCoverageResolvesDeletedSource() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.write(source: Self.detectedSource)
        try fixture.writeFile(relativePath: "Sources/Keep.swift", content: Self.cleanSource)
        _ = try fixture.commitAll(message: "add observed and clean sources")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(initial.findings.first)

        try fixture.removeFile(relativePath: "Sources/Input.swift")
        _ = try fixture.commitAll(message: "delete observed source")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)

        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let current = try #require(persisted.finding(id: finding.id))
        #expect(current.lifecycleState == .resolved)
        #expect(current.evidenceState == .verifiedAbsent)
        let latestSnapshot = try #require(Self.latestSnapshot(in: persisted))
        #expect(
            latestSnapshot.provenance.sourceDeletions.map(\.priorSourcePath.rawValue) == [
                "Sources/Input.swift"
            ])
        let selection = try #require(latestSnapshot.provenance.sourceSelection)
        #expect(selection.kind == .directory)
        #expect(selection.repositoryRelativeRoot == nil)
        #expect(selection.excludedPathPrefixes.isEmpty)
        guard case .resolved(let evidence) = current.events.last?.transition else {
            Issue.record("Expected complete relocation coverage to resolve the Finding")
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
        #expect(explanation.standardOutput.contains("Sources/Input.swift"))
        let inspection = try runLifecycleCLI([
            "lifecycle", "snapshot", fixture.artifact.path, latestSnapshot.id.rawValue,
        ])
        #expect(inspection.standardOutput.contains("Deleted SourceUnit: Sources/Input.swift"))
    }

    @Test("AT-11 directory coverage cannot resolve a deleted SourceUnit")
    func directoryCoverageCannotResolveDeletedSource() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.writeFile(relativePath: "Sources/Feature/Input.swift", content: Self.detectedSource)
        try fixture.writeFile(relativePath: "Sources/Feature/Keep.swift", content: Self.cleanSource)
        try fixture.writeFile(relativePath: "Sources/Elsewhere.swift", content: Self.cleanSource)
        _ = try fixture.commitAll(message: "add observed feature source")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(initial.findings.first)

        try fixture.removeFile(relativePath: "Sources/Feature/Input.swift")
        _ = try fixture.commitAll(message: "delete observed feature source")
        let featureDirectory = fixture.repository.appendingPathComponent("Sources/Feature")
        #expect(try analyze(repository: featureDirectory, artifact: fixture.artifact).status == 0)

        let persisted = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let current = try #require(persisted.finding(id: finding.id))
        #expect(current.lifecycleState == .open)
        #expect(current.evidenceState == .unverified)
        let latestSnapshot = try #require(Self.latestSnapshot(in: persisted))
        #expect(
            latestSnapshot.provenance.sourceDeletions.map(\.priorSourcePath.rawValue) == [
                "Sources/Feature/Input.swift"
            ])
        let selection = try #require(latestSnapshot.provenance.sourceSelection)
        #expect(selection.kind == .directory)
        #expect(selection.repositoryRelativeRoot?.rawValue == "Sources/Feature")
        #expect(selection.excludedPathPrefixes.isEmpty)
        guard case .unverified(let reasons) = current.events.last?.transition else {
            Issue.record("Expected incomplete relocation coverage to remain unverified")
            return
        }
        #expect(
            reasons.map(\.code) == [
                "relocation-coverage-incomplete",
                "scope-incomplete",
                "source-deleted",
            ])
        let explanation = try explainLifecycle(finding.id.rawValue, fixture: fixture)
        #expect(explanation.standardOutput.contains("source-deleted"))
        #expect(explanation.standardOutput.contains("relocation-coverage-incomplete"))
        #expect(explanation.standardOutput.contains("Sources/Feature/Input.swift"))
    }

    @Test("A resolution with removed deletion evidence fails closed")
    func removedDeletionEvidenceFailsClosed() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.write(source: Self.detectedSource)
        try fixture.writeFile(relativePath: "Sources/Keep.swift", content: Self.cleanSource)
        _ = try fixture.commitAll(message: "add observed and clean sources")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)

        try fixture.removeFile(relativePath: "Sources/Input.swift")
        _ = try fixture.commitAll(message: "delete observed source")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)

        let store = LifecycleArtifactStore(artifactURL: fixture.artifact)
        let artifact = try store.load()
        let latestSnapshot = try #require(Self.latestSnapshot(in: artifact))
        var root = try artifactJSONObject(at: fixture.artifact)
        var snapshots = try #require(root["snapshots"] as? [[String: Any]])
        let index = try #require(
            snapshots.firstIndex(where: { $0["id"] as? String == latestSnapshot.id.rawValue })
        )
        var snapshot = snapshots[index]
        var provenance = try #require(snapshot["provenance"] as? [String: Any])
        provenance["sourceDeletions"] = []
        snapshot["provenance"] = provenance
        snapshots[index] = snapshot
        root["snapshots"] = snapshots
        try lifecycleJSONData(root).write(to: fixture.artifact, options: .atomic)

        #expect(throws: LifecycleStoreError.self) { try store.load() }
    }

    private func analyze(
        repository: URL,
        artifact: URL,
        exclusions: [String] = []
    ) throws -> LifecycleCLIRunResult {
        var arguments = [
            "analyze", repository.path,
            "--format", "json",
            "--lifecycle-artifact", artifact.path,
            "--jobs", "2",
        ]
        for exclusion in exclusions {
            arguments += ["--exclude", exclusion]
        }
        return try runLifecycleCLI(arguments)
    }

    private static func latestSnapshot(in artifact: LifecycleArtifact) -> ObservationSnapshot? {
        artifact.snapshots.max {
            $0.provenance.lineage.sequence < $1.provenance.lineage.sequence
        }
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """

    private static let cleanSource = """
        func clean() -> Int { 1 }
        """
}
