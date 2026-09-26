import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 lifecycle reconciliation profiling CLI")
struct LifecycleReconciliationProfilingCLIWorkflowTests {
    @Test("Opt-in profiling preserves canonical artifact bytes and replay records no work")
    func profilingDoesNotChangeLifecycleEvidence() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.forcedTrySource, message: "add forced try")
        let plainArtifact = fixture.directory.appendingPathComponent("plain.json")
        let profiledArtifact = fixture.directory.appendingPathComponent("profiled.json")
        let profileURL = fixture.directory.appendingPathComponent("profile.json")

        let plain = try analyze(fixture, artifact: plainArtifact)
        let profiled = try analyze(fixture, artifact: profiledArtifact, profile: profileURL)

        #expect(plain.status == 0, "\(plain.standardError)")
        #expect(profiled.status == 0, "\(profiled.standardError)")
        #expect(plain.standardOutput == profiled.standardOutput)
        let canonicalBytes = try Data(contentsOf: profiledArtifact)
        #expect(try Data(contentsOf: plainArtifact) == canonicalBytes)
        #expect(try profiles(at: profileURL).count == 1)
        let first = try #require(try profiles(at: profileURL).first)
        #expect(first["detections"] as? Int == 1)
        #expect(first["candidates"] as? Int == 0)
        #expect(first["evaluatedPairs"] as? Int == 0)
        #expect(first["newFindings"] as? Int == 1)
        #expect(first["uniqueContinuities"] as? Int == 0)

        let replay = try analyze(fixture, artifact: profiledArtifact, profile: profileURL)
        #expect(replay.status == 0, "\(replay.standardError)")
        #expect(try profiles(at: profileURL).isEmpty)
        #expect(try Data(contentsOf: profiledArtifact) == canonicalBytes)
    }

    @Test("A unique rename and copied declaration expose distinct reconciliation counts")
    func uniqueAndAmbiguousCountsFollowRealCLI() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let artifactURL = fixture.directory.appendingPathComponent("lifecycle.json")
        let profileURL = fixture.directory.appendingPathComponent("profile.json")
        _ = try fixture.commit(source: Self.forcedTrySource, message: "add forced try")
        #expect(try analyze(fixture, artifact: artifactURL, profile: profileURL).status == 0)

        try fixture.runGit(["mv", "Sources/Input.swift", "Sources/Renamed.swift"])
        _ = try fixture.commitAll(message: "rename source")
        let renamed = try analyze(fixture, artifact: artifactURL, profile: profileURL)
        #expect(renamed.status == 0, "\(renamed.standardError)")
        #expect(try profiles(at: profileURL).count == 1)
        let unique = try #require(try profiles(at: profileURL).first)
        #expect(unique["detections"] as? Int == 1)
        #expect(unique["candidates"] as? Int == 1)
        #expect(unique["evaluatedPairs"] as? Int == 1)
        #expect(unique["crediblePairs"] as? Int == 1)
        #expect(unique["uniqueContinuities"] as? Int == 1)
        #expect(unique["ambiguousGroups"] as? Int == 0)

        try fixture.writeFile(relativePath: "Sources/Copy.swift", content: Self.forcedTrySource)
        _ = try fixture.commitAll(message: "copy declaration")
        let copied = try analyze(fixture, artifact: artifactURL, profile: profileURL)
        #expect(copied.status == 0, "\(copied.standardError)")
        #expect(try profiles(at: profileURL).count == 1)
        let ambiguous = try #require(try profiles(at: profileURL).first)
        #expect(ambiguous["detections"] as? Int == 2)
        #expect(ambiguous["candidates"] as? Int == 1)
        #expect(ambiguous["evaluatedPairs"] as? Int == 2)
        #expect(ambiguous["crediblePairs"] as? Int == 2)
        #expect(ambiguous["uniqueContinuities"] as? Int == 0)
        #expect(ambiguous["newFindings"] as? Int == 0)
        #expect(ambiguous["unresolvedDetections"] as? Int == 2)
        #expect(ambiguous["ambiguousGroups"] as? Int == 1)
        #expect((ambiguous["reconciliationElapsedNanoseconds"] as? NSNumber)?.uint64Value ?? 0 > 0)

        let artifact = try LifecycleArtifactStore(artifactURL: artifactURL).load()
        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 2)
    }

    private func analyze(
        _ fixture: TemporaryLifecycleGitRepository,
        artifact: URL,
        profile: URL? = nil
    ) throws -> LifecycleCLIRunResult {
        var arguments = [
            "analyze", fixture.repository.path, "--format", "json",
            "--lifecycle-artifact", artifact.path, "--jobs", "2",
        ]
        if let profile { arguments += ["--profile-output", profile.path] }
        return try runLifecycleCLI(arguments)
    }

    private func profiles(at url: URL) throws -> [[String: Any]] {
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        return try #require(object["lifecycleReconciliation"] as? [[String: Any]])
    }

    private static let forcedTrySource = """
        func load() throws -> Int { 1 }
        func run() {
            _ = try! load()
        }
        """
}
