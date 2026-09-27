import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 Git introduction profile output safety")
struct IntroductionProfileOutputSafetyCLIWorkflowTests {
    @Test("Profile output cannot replace the lifecycle artifact lock")
    func profileCannotReplaceArtifactLock() throws {
        let prepared = try preparedFixture()
        let lockURL = URL(fileURLWithPath: prepared.artifact.path + ".lock")
        let originalLockBytes = try Data(contentsOf: lockURL)

        let result = try inferIntroduction(
            prepared.findingID,
            repository: prepared.fixture.repository,
            artifact: prepared.artifact,
            profile: lockURL
        )

        #expect(result.status == 2)
        #expect(result.standardError.contains("must not replace the lifecycle artifact, lock"))
        #expect(try Data(contentsOf: prepared.artifact) == prepared.artifactBytes)
        #expect(try Data(contentsOf: lockURL) == originalLockBytes)
        var isDirectory: ObjCBool = true
        #expect(FileManager.default.fileExists(atPath: lockURL.path, isDirectory: &isDirectory))
        #expect(!isDirectory.boolValue)
    }

    @Test("Profile output cannot replace a Swift source")
    func profileCannotReplaceSwiftSource() throws {
        let prepared = try preparedFixture()
        let sourceURL = prepared.fixture.directory.appendingPathComponent("protected.swift")
        let sourceBytes = Data("let protectedValue = 1\n".utf8)
        try sourceBytes.write(to: sourceURL, options: .atomic)

        let result = try inferIntroduction(
            prepared.findingID,
            repository: prepared.fixture.repository,
            artifact: prepared.artifact,
            profile: sourceURL
        )

        #expect(result.status == 2)
        #expect(result.standardError.contains("must not replace the lifecycle artifact, lock, or a Swift source"))
        #expect(try Data(contentsOf: prepared.artifact) == prepared.artifactBytes)
        #expect(try Data(contentsOf: sourceURL) == sourceBytes)
    }

    @Test("Profile output cannot replace an existing directory")
    func profileCannotReplaceDirectory() throws {
        let prepared = try preparedFixture()
        let directoryURL = prepared.fixture.directory.appendingPathComponent(
            "protected-profile",
            isDirectory: true
        )
        let sentinelURL = directoryURL.appendingPathComponent("sentinel.txt")
        let sentinelBytes = Data("do not delete\n".utf8)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try sentinelBytes.write(to: sentinelURL, options: .atomic)

        let result = try inferIntroduction(
            prepared.findingID,
            repository: prepared.fixture.repository,
            artifact: prepared.artifact,
            profile: directoryURL
        )

        #expect(result.status == 2)
        #expect(result.standardError.contains("Introduction profile output path is a directory"))
        #expect(try Data(contentsOf: prepared.artifact) == prepared.artifactBytes)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try Data(contentsOf: sentinelURL) == sentinelBytes)
    }

    private func preparedFixture() throws -> (
        fixture: TemporaryLifecycleGitRepository,
        artifact: URL,
        findingID: FindingID,
        artifactBytes: Data
    ) {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "introduce forced try")
        let artifact = fixture.directory.appendingPathComponent("lifecycle.json")
        let analysis = try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", artifact.path,
            "--jobs", "2",
        ])
        #expect(analysis.status == 0, "\(analysis.standardError)")
        let stored = try LifecycleArtifactStore(artifactURL: artifact).load()
        let finding = try #require(stored.findings.first)
        return (fixture, artifact, finding.id, try Data(contentsOf: artifact))
    }

    private func inferIntroduction(
        _ findingID: FindingID,
        repository: URL,
        artifact: URL,
        profile: URL
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "lifecycle", "infer-introduction",
            artifact.path,
            findingID.rawValue,
            "--repository", repository.path,
            "--max-revisions", "4",
            "--profile-output", profile.path,
        ])
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """
}
