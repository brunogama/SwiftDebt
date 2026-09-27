import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 optional Git blame capability CLI acceptance")
struct AgedForceTryOptionalProviderCLIWorkflowTests {
    @Test("AT-26 provider loss keeps aged force try debt open until evidence returns")
    func providerLossRemainsUnverifiedUntilRestored() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let git = "/usr/bin/git"
        #expect(FileManager.default.isExecutableFile(atPath: git))

        let firstRevision = try fixture.commit(
            source: Self.detectedSource,
            message: "add forced try"
        )
        try fixture.writeFile(relativePath: "README.md", content: "first unrelated change\n")
        let detectedHead = try fixture.commitAll(message: "change unrelated documentation")
        #expect(firstRevision != detectedHead)

        let detected = try analyze(fixture, gitBlameProvider: git)
        #expect(detected.status == 0, "\(detected.standardError)\n\(detected.standardOutput)")
        var artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(
            artifact.findings.first { $0.rule.identity.description == "swiftdebt.aged-force-try" }
        )
        let firstSnapshot = try #require(artifact.snapshots.first)
        #expect(firstSnapshot.provenance.capabilities.map(\.name) == ["git-blame-v1", "syntax-analysis"])
        #expect(
            firstSnapshot.detections.contains { detection in
                detection.rule.identity.description == "swiftdebt.aged-force-try"
                    && detection.message.contains("predates the captured Git HEAD")
            })
        let introduction = try runLifecycleCLI([
            "lifecycle", "infer-introduction", fixture.artifact.path, finding.id.rawValue,
            "--repository", fixture.repository.path,
            "--max-revisions", "8",
        ])
        #expect(introduction.status == 0)
        #expect(introduction.standardOutput.contains("Introduction: unavailable"))
        #expect(introduction.standardOutput.contains("historical-capability-incomparable"))

        _ = try fixture.commit(source: Self.resolvedSource, message: "remove forced try")
        let unavailable = try analyze(fixture, gitBlameProvider: nil)
        #expect(unavailable.status == 2, "\(unavailable.standardError)\n\(unavailable.standardOutput)")

        artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let unavailableSnapshot = try #require(
            artifact.snapshots.first { $0.provenance.lineage.sequence == 2 }
        )
        let capability = try #require(
            unavailableSnapshot.provenance.capabilities.first { $0.name == "git-blame-v1" }
        )
        guard case .unavailable(let capabilityReason) = capability.state else {
            Issue.record("Expected omitted Git blame provider to be unavailable")
            return
        }
        #expect(capabilityReason.code == "git-blame-provider-omitted")
        let atomic = try #require(
            unavailableSnapshot.atomicObservations.first {
                $0.rule.identity.description == "swiftdebt.aged-force-try"
            }
        )
        guard case .unsupported(let atomicReason) = atomic.outcome else {
            Issue.record("Expected selected aged-force-try rule to remain explicitly unsupported")
            return
        }
        #expect(atomicReason.message.contains("--git-blame-provider"))
        let unverifiedFinding = try #require(artifact.finding(id: finding.id))
        #expect(unverifiedFinding.lifecycleState == .open)
        #expect(unverifiedFinding.evidenceState == .unverified)

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.artifact.path, finding.id.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("git-blame-v1"))
        #expect(explanation.standardOutput.contains("git-blame-provider-omitted"))

        try fixture.writeFile(relativePath: "README.md", content: "second unrelated change\n")
        _ = try fixture.commitAll(message: "change unrelated documentation again")
        let restored = try analyze(fixture, gitBlameProvider: git)
        #expect(restored.status == 0, "\(restored.standardError)\n\(restored.standardOutput)")

        artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let resolvedFinding = try #require(artifact.finding(id: finding.id))
        #expect(resolvedFinding.lifecycleState == .resolved)
        #expect(resolvedFinding.evidenceState == .verifiedAbsent)
        #expect(resolvedFinding.events.map(\.transition.kind) == [.opened, .unverified, .resolved])
    }

    private func analyze(
        _ fixture: TemporaryLifecycleGitRepository,
        gitBlameProvider: String?
    ) throws -> LifecycleCLIRunResult {
        var arguments = [
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
            "--aged-force-try",
            "--jobs", "2",
        ]
        if let gitBlameProvider {
            arguments += ["--git-blame-provider", gitBlameProvider]
        }
        return try runLifecycleCLI(arguments)
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """

    private static let resolvedSource = """
        func load() throws -> Int { 1 }
        func run() throws { _ = try load() }
        """
}
