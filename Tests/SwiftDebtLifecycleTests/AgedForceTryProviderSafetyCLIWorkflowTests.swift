import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 optional Git blame capability safety")
struct AgedForceTryProviderSafetyCLIWorkflowTests {
    @Test("Repository ignored revisions cannot fabricate an aged force try")
    func ignoredRevisionsAreDisabled() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let firstRevision = try fixture.commit(
            source: Self.safeSource,
            message: "add handled error"
        )
        let head = try fixture.commit(
            source: Self.headIntroducedForceTry,
            message: "introduce forced try"
        )
        try fixture.writeFile(relativePath: ".git/ignore-revs", content: head + "\n")
        try fixture.runGit(["config", "blame.ignoreRevsFile", ".git/ignore-revs"])

        let configuredBlame = try fixture.gitOutput([
            "blame", "--line-porcelain", head, "--", "Sources/Input.swift",
        ])
        #expect(configuredBlame.hasPrefix(firstRevision))
        let exactBlame = try fixture.gitOutput([
            "blame", "--no-ignore-revs-file", "--line-porcelain", head, "--", "Sources/Input.swift",
        ])
        #expect(exactBlame.hasPrefix(head))

        let result = try analyze(fixture, provider: "/usr/bin/git")

        #expect(result.status == 0, "\(result.standardError)\n\(result.standardOutput)")
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let snapshot = try #require(artifact.snapshots.first)
        #expect(snapshot.provenance.capabilities.first { $0.name == "git-blame-v1" }?.state == .available)
        #expect(
            !snapshot.detections.contains {
                $0.rule.identity.description == "swiftdebt.aged-force-try"
            }
        )
    }

    @Test("Analysis outputs cannot replace the Git blame provider")
    func outputsPreserveProviderBytes() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.headIntroducedForceTry, message: "add forced try")
        let provider = fixture.directory.appendingPathComponent("git-provider")
        let providerBytes = Data("#!/bin/sh\nexec /usr/bin/git \"$@\"\n".utf8)
        try providerBytes.write(to: provider, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: provider.path
        )

        for outputOption in ["--output", "--profile-output", "--lifecycle-artifact"] {
            let result = try runLifecycleCLI([
                "analyze", fixture.repository.path,
                "--format", "json",
                "--aged-force-try",
                "--git-blame-provider", provider.path,
                outputOption, provider.path,
                "--jobs", "2",
            ])

            #expect(result.status == 2, "\(outputOption): \(result.standardError)")
            #expect(try Data(contentsOf: provider) == providerBytes)
        }
    }

    private func analyze(
        _ fixture: TemporaryLifecycleGitRepository,
        provider: String
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
            "--aged-force-try",
            "--git-blame-provider", provider,
            "--jobs", "2",
        ])
    }

    private static let safeSource = """
        func load() throws -> Int { 1 }; func run() throws { _ = try load() }
        """

    private static let headIntroducedForceTry = """
        func load() throws -> Int { 1 }; func run() { _ = try! load() }
        """
}
