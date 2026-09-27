import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 Git introduction profile CLI acceptance")
struct IntroductionProfileCLIWorkflowTests {
    @Test("Introduction profiling reports repeated analysis without claiming cache reuse")
    func introductionProfileMeasuresCurrentReuseTruthfully() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.absentSource, message: "add clean implementation")
        _ = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(original.findings.first)
        let profileURL = fixture.directory.appendingPathComponent("introduction-profile.json")

        let first = try inferIntroduction(
            finding.id,
            repository: fixture.repository,
            artifact: fixture.artifact,
            maximumRevisions: 4,
            profile: profileURL
        )

        #expect(first.status == 0, "\(first.standardError)")
        let accepted = try introductionProfile(at: profileURL)
        #expect(accepted["reportKind"] as? String == "swiftdebt-lifecycle-introduction-profile")
        #expect(accepted["schemaVersion"] as? Int == 1)
        #expect(accepted["findingID"] as? String == finding.id.rawValue)
        #expect(accepted["maximumRevisions"] as? Int == 4)
        #expect(accepted["maximumFileBytes"] as? Int == 16 * 1_024 * 1_024)
        #expect(accepted["evidenceRevisionCount"] as? Int == 2)
        #expect(accepted["analyzedRevisionCount"] as? Int == 2)
        #expect(accepted["reusedRevisionCount"] as? Int == 0)
        #expect(accepted["frontierRevisionCount"] as? Int == 0)
        #expect(accepted["recordingStatus"] as? String == "accepted")
        #expect((accepted["operationElapsedNanoseconds"] as? NSNumber)?.uint64Value ?? 0 > 0)
        let exactBytes = try Data(contentsOf: fixture.artifact)

        let repeated = try inferIntroduction(
            finding.id,
            repository: fixture.repository,
            artifact: fixture.artifact,
            maximumRevisions: 4,
            profile: profileURL
        )

        #expect(repeated.status == 0, "\(repeated.standardError)")
        let alreadyPresent = try introductionProfile(at: profileURL)
        #expect(alreadyPresent["recordingStatus"] as? String == "already-present")
        #expect(alreadyPresent["evidenceRevisionCount"] as? Int == 2)
        #expect(alreadyPresent["analyzedRevisionCount"] as? Int == 2)
        #expect(alreadyPresent["reusedRevisionCount"] as? Int == 0)
        #expect(repeated.standardOutput == first.standardOutput)
        #expect(try Data(contentsOf: fixture.artifact) == exactBytes)
    }

    @Test("A failure after profile preparation cannot leave stale passing measurements")
    func preparedProfileIsRemovedWhenArtifactRecordingFails() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.findings.first)
        let originalBytes = try Data(contentsOf: fixture.artifact)
        let profileURL = fixture.directory.appendingPathComponent("introduction-profile.json")
        try FileManager.default.removeItem(
            at: URL(fileURLWithPath: fixture.artifact.path + ".lock")
        )
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: fixture.artifact.path + ".lock"),
            withIntermediateDirectories: true
        )
        try #"{"reportKind":"stale-pass"}"#.write(
            to: profileURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try inferIntroduction(
            finding.id,
            repository: fixture.repository,
            artifact: fixture.artifact,
            maximumRevisions: 4,
            profile: profileURL
        )

        #expect(result.status == 2)
        #expect(!FileManager.default.fileExists(atPath: profileURL.path))
        #expect(try Data(contentsOf: fixture.artifact) == originalBytes)
    }

    @Test("A profile inside the actual repository is rejected from a subdirectory query")
    func profileInsideActualRepositoryIsRejected() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        #expect(try analyze(repository: fixture.repository, artifact: fixture.artifact).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(original.findings.first)
        let originalBytes = try Data(contentsOf: fixture.artifact)
        let profileURL = fixture.repository.appendingPathComponent("introduction-profile.json")
        let sourceDirectory = fixture.repository.appendingPathComponent("Sources", isDirectory: true)
        try "do not delete\n".write(to: profileURL, atomically: true, encoding: .utf8)

        let result = try inferIntroduction(
            finding.id,
            repository: sourceDirectory,
            artifact: fixture.artifact,
            maximumRevisions: 4,
            profile: profileURL
        )

        #expect(result.status == 2)
        #expect(result.standardError.contains("outside the analyzed repository"))
        #expect(try String(contentsOf: profileURL, encoding: .utf8) == "do not delete\n")
        #expect(try Data(contentsOf: fixture.artifact) == originalBytes)
    }

    @Test("Profile output cannot replace an external artifact")
    func profileCannotReplaceExternalArtifact() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        let artifact = fixture.directory.appendingPathComponent("lifecycle.json")
        #expect(try analyze(repository: fixture.repository, artifact: artifact).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: artifact).load()
        let finding = try #require(original.findings.first)
        let originalBytes = try Data(contentsOf: artifact)

        let exactResult = try inferIntroduction(
            finding.id,
            repository: fixture.repository,
            artifact: artifact,
            maximumRevisions: 4,
            profile: artifact
        )

        #expect(exactResult.status == 2)
        #expect(exactResult.standardError.contains("must not replace the lifecycle artifact"))
        #expect(try Data(contentsOf: artifact) == originalBytes)
        let values = try fixture.directory.resourceValues(
            forKeys: [.volumeSupportsCaseSensitiveNamesKey]
        )
        guard values.volumeSupportsCaseSensitiveNames == false else { return }
        let profileURL = fixture.directory.appendingPathComponent("LIFECYCLE.json")

        let result = try inferIntroduction(
            finding.id,
            repository: fixture.repository,
            artifact: artifact,
            maximumRevisions: 4,
            profile: profileURL
        )

        #expect(result.status == 2)
        #expect(result.standardError.contains("must not replace the lifecycle artifact"))
        #expect(try Data(contentsOf: artifact) == originalBytes)
    }

    private func inferIntroduction(
        _ findingID: FindingID,
        repository: URL,
        artifact: URL,
        maximumRevisions: Int,
        profile: URL
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "lifecycle", "infer-introduction",
            artifact.path,
            findingID.rawValue,
            "--repository", repository.path,
            "--max-revisions", String(maximumRevisions),
            "--profile-output", profile.path,
        ])
    }

    private func introductionProfile(at url: URL) throws -> [String: Any] {
        try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
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
}
