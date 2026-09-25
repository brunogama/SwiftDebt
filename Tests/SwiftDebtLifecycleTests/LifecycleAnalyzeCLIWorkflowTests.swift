import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 analyze-to-lifecycle CLI acceptance")
struct LifecycleAnalyzeCLIWorkflowTests {
    @Test("Inherited Git environment cannot hide a real repository")
    func inheritedGitEnvironmentDoesNotHideRepository() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let revision = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_DIR"] = fixture.repository.appendingPathComponent("missing-git-dir").path

        let result = try runLifecycleCLI(
            [
                "analyze", fixture.repository.path,
                "--format", "json",
                "--lifecycle-artifact", fixture.artifact.path,
                "--jobs", "2",
            ], environment: environment)

        #expect(result.status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let snapshot = try #require(artifact.snapshots.first)
        guard case .git(let observedRevision, _, _) = snapshot.provenance.sourceIdentity else {
            Issue.record("Expected authoritative Git identity despite inherited GIT_DIR")
            return
        }
        #expect(observedRevision.rawValue == revision)
    }

    @Test("Real Git analyses persist authoritative provenance, resolve, and replay exactly")
    func analyzePersistsAndReplaysLifecycle() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let firstRevision = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        let schemaTwoBaseline = try analyzeWithoutLifecycle(fixture.repository)

        let firstRun = try analyze(fixture)
        #expect(firstRun.status == 0)
        #expect(firstRun.standardError.isEmpty)
        #expect(firstRun.standardOutput == schemaTwoBaseline.standardOutput)
        let firstArtifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let firstSnapshot = try #require(firstArtifact.snapshots.first)
        #expect(firstArtifact.snapshots.count == 1)
        #expect(firstArtifact.findings.count == 1)
        #expect(firstSnapshot.provenance.scope == .repository)
        #expect(firstSnapshot.provenance.capabilities.map(\.name) == ["syntax-analysis"])
        guard case .git(let revision, let state, let sourceDigest) = firstSnapshot.provenance.sourceIdentity else {
            Issue.record("Expected AnalysisService to derive Git source identity")
            return
        }
        #expect(revision.rawValue == firstRevision)
        #expect(state == .clean)
        #expect(sourceDigest.value.count == 64)
        #expect(firstSnapshot.provenance.configurationFingerprint.value.count == 64)

        let firstBytes = try Data(contentsOf: fixture.artifact)
        let firstReplay = try analyze(fixture)
        #expect(firstReplay.status == 0)
        #expect(try Data(contentsOf: fixture.artifact) == firstBytes)
        let gatedReplay = try analyze(fixture, failOnViolation: true)
        #expect(gatedReplay.status == 1)
        #expect(gatedReplay.standardOutput == schemaTwoBaseline.standardOutput)
        #expect(try Data(contentsOf: fixture.artifact) == firstBytes)
        let generatedOutputReplay = try analyze(fixture, writeGeneratedOutputs: true)
        #expect(generatedOutputReplay.status == 0)
        #expect(try Data(contentsOf: fixture.artifact) == firstBytes)
        #expect(FileManager.default.fileExists(atPath: generatedReportURL(for: fixture.repository).path))
        #expect(FileManager.default.fileExists(atPath: generatedProfileURL(for: fixture.repository).path))
        #expect(FileManager.default.fileExists(atPath: generatedStampURL(for: fixture.repository).path))

        let secondRevision = try fixture.commit(source: Self.resolvedSource, message: "remove forced try")
        let secondRun = try analyze(fixture, writeGeneratedOutputs: true)
        #expect(secondRun.status == 0)
        #expect(secondRun.standardError.isEmpty)
        let resolvedArtifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        #expect(resolvedArtifact.snapshots.count == 2)
        let secondSnapshot = try #require(
            resolvedArtifact.snapshots.first { $0.provenance.lineage.sequence == 2 }
        )
        #expect(secondSnapshot.provenance.lineage.predecessorSnapshotID == firstSnapshot.id)
        guard case .git(let revision, let state, _) = secondSnapshot.provenance.sourceIdentity else {
            Issue.record("Expected the successor to retain Git source identity")
            return
        }
        #expect(revision.rawValue == secondRevision)
        #expect(state == .clean)
        let finding = try #require(resolvedArtifact.findings.first)
        #expect(finding.lifecycleState == .resolved)
        #expect(finding.evidenceState == .verifiedAbsent)
        #expect(finding.events.map(\.transition.kind) == [.opened, .resolved])

        let inventory = try runLifecycleCLI([
            "lifecycle", "inventory", fixture.artifact.path,
        ])
        #expect(inventory.status == 0)
        #expect(inventory.standardOutput.contains("resolved verified-absent"))
        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.artifact.path, finding.id.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("State: resolved"))
        #expect(explanation.standardOutput.contains("complete-comparable-absence"))
        let inspection = try runLifecycleCLI([
            "lifecycle", "snapshot", fixture.artifact.path, secondSnapshot.id.rawValue,
        ])
        #expect(inspection.status == 0)
        #expect(inspection.standardOutput.contains("Git revision: \(secondRevision) (clean)"))
        #expect(inspection.standardOutput.contains("Capability syntax-analysis: available"))

        let resolvedBytes = try Data(contentsOf: fixture.artifact)
        let secondReplay = try analyze(fixture, writeGeneratedOutputs: true)
        #expect(secondReplay.status == 0)
        #expect(try Data(contentsOf: fixture.artifact) == resolvedBytes)
    }

    @Test("A dirty successor is rejected when source order cannot be proven")
    func dirtySuccessorFailsClosed() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture).status == 0)
        let original = try Data(contentsOf: fixture.artifact)
        try fixture.write(source: Self.resolvedSource)

        let result = try analyze(fixture)

        #expect(result.status == 2)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("dirty working tree cannot establish a lifecycle successor"))
        #expect(try Data(contentsOf: fixture.artifact) == original)
    }

    @Test("A dirty initial Git snapshot cannot seed an unextendable lineage")
    func dirtyInitialSnapshotFailsClosed() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        try fixture.write(source: Self.resolvedSource)

        let result = try analyze(fixture)

        #expect(result.status == 2)
        #expect(result.standardError.contains("dirty working tree cannot seed"))
        #expect(!FileManager.default.fileExists(atPath: fixture.artifact.path))
    }

    @Test("A skipped Package.swift makes repository coverage partial")
    func skippedPackageManifestDoesNotProveResolution() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        try fixture.writeFile(relativePath: "Package.swift", content: "let omitted = try! load()\n")
        try fixture.runGit(["add", "Package.swift"])
        _ = try fixture.commit(source: Self.detectedSource, message: "add sources")

        #expect(try analyze(fixture).status == 0)
        let initial = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let scope = try #require(initial.snapshots.first?.provenance.scope)
        guard case .partial(let reason) = scope else {
            Issue.record("Expected partial scope when Package.swift is skipped")
            return
        }
        #expect(reason.message.contains("Package.swift"))

        _ = try fixture.commit(source: Self.resolvedSource, message: "remove source violation")
        #expect(try analyze(fixture).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .unverified)
    }

    @Test("A tracked report output remains visible to Git provenance")
    func trackedOutputIsNotExcluded() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let trackedOutput = fixture.repository.appendingPathComponent("Reports/debt.json")
        try fixture.writeFile(relativePath: "Reports/debt.json", content: "{}\n")
        try fixture.runGit(["add", "Reports/debt.json"])
        _ = try fixture.commit(source: Self.detectedSource, message: "add source and report placeholder")
        let arguments = [
            "analyze", fixture.repository.path,
            "--format", "json",
            "--output", trackedOutput.path,
            "--lifecycle-artifact", fixture.artifact.path,
            "--jobs", "2",
        ]

        #expect(try runLifecycleCLI(arguments).status == 0)
        let originalArtifact = try Data(contentsOf: fixture.artifact)
        let replay = try runLifecycleCLI(arguments)

        #expect(replay.status == 2)
        #expect(replay.standardError.contains("dirty working tree cannot establish a lifecycle successor"))
        #expect(try Data(contentsOf: fixture.artifact) == originalArtifact)
    }

    @Test("A merge successor is rejected until multi-parent lineage is modeled")
    func mergeSuccessorFailsClosed() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture).status == 0)
        let original = try Data(contentsOf: fixture.artifact)
        let mainBranch = try fixture.gitOutput(["branch", "--show-current"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.runGit(["checkout", "-b", "lifecycle-side"])
        try fixture.runGit(["commit", "--allow-empty", "-m", "side change"])
        try fixture.runGit(["checkout", mainBranch])
        try fixture.runGit(["commit", "--allow-empty", "-m", "main change"])
        try fixture.runGit(["merge", "--no-ff", "lifecycle-side", "-m", "merge histories"])

        let result = try analyze(fixture)

        #expect(result.status == 2)
        #expect(result.standardError.contains("merge commits require explicit multi-parent lineage support"))
        #expect(try Data(contentsOf: fixture.artifact) == original)
    }

    @Test("A disconnected repository cannot become a successor by arrival order")
    func disconnectedRepositoryFailsClosed() throws {
        let recorded = try TemporaryLifecycleGitRepository()
        _ = try recorded.commit(source: Self.detectedSource, message: "recorded history")
        #expect(try analyze(recorded).status == 0)
        let original = try Data(contentsOf: recorded.artifact)
        let disconnected = try TemporaryLifecycleGitRepository()
        _ = try disconnected.commit(source: Self.resolvedSource, message: "unrelated history")

        let result = try analyze(repository: disconnected.repository, artifact: recorded.artifact)

        #expect(result.status == 2)
        #expect(result.standardError.contains("revision has no parent present in this nonempty artifact"))
        #expect(try Data(contentsOf: recorded.artifact) == original)
    }

    private func analyze(
        _ fixture: TemporaryLifecycleGitRepository,
        failOnViolation: Bool = false,
        writeGeneratedOutputs: Bool = false
    ) throws -> LifecycleCLIRunResult {
        try analyze(
            repository: fixture.repository,
            artifact: fixture.artifact,
            failOnViolation: failOnViolation,
            writeGeneratedOutputs: writeGeneratedOutputs
        )
    }

    private func analyze(
        repository: URL,
        artifact: URL,
        failOnViolation: Bool = false,
        writeGeneratedOutputs: Bool = false
    ) throws -> LifecycleCLIRunResult {
        var arguments = [
            "analyze", repository.path,
            "--format", "json",
            "--lifecycle-artifact", artifact.path,
            "--jobs", "2",
        ]
        if failOnViolation { arguments.append("--fail-on-violation") }
        if writeGeneratedOutputs {
            arguments += [
                "--output", generatedReportURL(for: repository).path,
                "--profile-output", generatedProfileURL(for: repository).path,
                "--stamp", generatedStampURL(for: repository).path,
            ]
        }
        return try runLifecycleCLI(arguments)
    }

    private func generatedReportURL(for repository: URL) -> URL {
        repository.appendingPathComponent(".swift-debt/report.json")
    }

    private func generatedProfileURL(for repository: URL) -> URL {
        repository.appendingPathComponent(".swift-debt/profile.json")
    }

    private func generatedStampURL(for repository: URL) -> URL {
        repository.appendingPathComponent("Generated/SwiftDebt.analysis.swift")
    }

    private func analyzeWithoutLifecycle(_ repository: URL) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", repository.path,
            "--format", "json",
            "--jobs", "2",
        ])
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """

    private static let resolvedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try? load() }
        """
}
