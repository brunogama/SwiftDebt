import Foundation
import SwiftDebtLifecycle
import Testing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@Suite("R3 public CLI replay and interrupted write")
struct LifecycleConcurrentCLIReplayTests {
    @Test("AT-22 concurrent duplicate CLI ingestion matches ordered canonical history")
    func concurrentReplayMatchesOrderedHistory() async throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let openingRevision = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        let resolvedRevision = try fixture.commit(source: Self.resolvedSource, message: "remove forced try")
        let orderedArtifact = fixture.directory.appendingPathComponent("ordered.json")
        let concurrentArtifact = fixture.directory.appendingPathComponent("concurrent.json")

        try fixture.runGit(["checkout", openingRevision])
        #expect(try analyze(fixture.repository, orderedArtifact, jobs: 1).status == 0)
        try fixture.runGit(["checkout", resolvedRevision])
        #expect(try analyze(fixture.repository, orderedArtifact, jobs: 1).status == 0)
        let expected = try Data(contentsOf: orderedArtifact)
        let ordered = try LifecycleArtifactStore(artifactURL: orderedArtifact).load()

        for revision in [openingRevision, resolvedRevision] {
            try fixture.runGit(["checkout", revision])
            let repositoryPath = fixture.repository.path
            let artifactPath = concurrentArtifact.path
            let results = try await withThrowingTaskGroup(of: LifecycleCLIRunResult.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        try runLifecycleCLI(Self.arguments(repositoryPath, artifactPath, jobs: 4))
                    }
                }
                var results: [LifecycleCLIRunResult] = []
                for try await result in group { results.append(result) }
                return results
            }
            #expect(results.count == 4)
            #expect(results.allSatisfy { $0.status == 0 }, "\(results.map(\.standardError))")
        }

        let concurrent = try LifecycleArtifactStore(artifactURL: concurrentArtifact).load()
        #expect(try Data(contentsOf: concurrentArtifact) == expected)
        #expect(concurrent.snapshots.map(\.id) == ordered.snapshots.map(\.id))
        #expect(concurrent.findings.map(\.id) == ordered.findings.map(\.id))
        #expect(concurrent.findings.map { $0.events.map(\.id) } == ordered.findings.map { $0.events.map(\.id) })
        #expect(concurrent.unresolvedDetections == ordered.unresolvedDetections)
        #expect(concurrent.snapshots.count == 2)
        #expect(concurrent.findings.count == 1)
        #expect(concurrent.findings.first?.events.map(\.transition.kind) == [.opened, .resolved])
    }

    @Test("An interrupted atomic artifact write preserves the prior history and retry is idempotent")
    func failedWritePreservesArtifactAndRetry() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let openingRevision = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        let resolvedRevision = try fixture.commit(source: Self.resolvedSource, message: "remove forced try")
        let expectedArtifact = fixture.directory.appendingPathComponent("expected.json")
        let interruptedArtifact = fixture.directory.appendingPathComponent("interrupted.json")

        try fixture.runGit(["checkout", openingRevision])
        #expect(try analyze(fixture.repository, expectedArtifact).status == 0)
        #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
        let priorBytes = try Data(contentsOf: interruptedArtifact)

        try fixture.runGit(["checkout", resolvedRevision])
        #expect(try analyze(fixture.repository, expectedArtifact).status == 0)
        let expectedBytes = try Data(contentsOf: expectedArtifact)
        let failed = try runLifecycleCLIWithFileSizeLimit(
            Self.arguments(fixture.repository.path, interruptedArtifact.path)
        )
        #expect(failed.status != 0)
        #expect(failed.standardError.contains("Unable to write lifecycle artifact"), "\(failed.standardError)")
        #expect(try Data(contentsOf: interruptedArtifact) == priorBytes)
        #expect(try LifecycleArtifactStore(artifactURL: interruptedArtifact).load().snapshots.count == 1)

        #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
        #expect(try Data(contentsOf: interruptedArtifact) == expectedBytes)
        #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
        #expect(try Data(contentsOf: interruptedArtifact) == expectedBytes)
    }

    @Test("A killed CLI waiting on the lifecycle lock leaves history intact for retry")
    func killedLockWaiterCanRetry() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        let openingRevision = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        let resolvedRevision = try fixture.commit(source: Self.resolvedSource, message: "remove forced try")
        let artifact = fixture.directory.appendingPathComponent("lock-wait.json")
        let profile = fixture.directory.appendingPathComponent("lock-wait-profile.json")

        try fixture.runGit(["checkout", openingRevision])
        #expect(try analyze(fixture.repository, artifact).status == 0)
        let priorBytes = try Data(contentsOf: artifact)

        try fixture.runGit(["checkout", resolvedRevision])
        let lockPath = artifact.path + ".lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        #expect(descriptor >= 0)
        guard descriptor >= 0 else { return }
        defer { _ = close(descriptor) }
        #expect(flock(descriptor, LOCK_EX) == 0)
        defer { _ = flock(descriptor, LOCK_UN) }

        let process = Process()
        process.executableURL = try lifecycleExecutableURL()
        process.arguments =
            Self.arguments(fixture.repository.path, artifact.path)
            + ["--profile-output", profile.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }

        let deadline = Date().addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath: profile.path)
            && process.isRunning && Date() < deadline
        {
            Thread.sleep(forTimeInterval: 0.01)
        }
        #expect(FileManager.default.fileExists(atPath: profile.path))
        #expect(process.isRunning)
        guard process.isRunning else { return }
        _ = kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(try Data(contentsOf: artifact) == priorBytes)

        _ = flock(descriptor, LOCK_UN)
        #expect(try analyze(fixture.repository, artifact).status == 0)
        let completedBytes = try Data(contentsOf: artifact)
        #expect(try analyze(fixture.repository, artifact).status == 0)
        #expect(try Data(contentsOf: artifact) == completedBytes)
        #expect(try LifecycleArtifactStore(artifactURL: artifact).load().snapshots.count == 2)
    }

    private static func arguments(_ repository: String, _ artifact: String, jobs: Int = 2) -> [String] {
        ["analyze", repository, "--format", "json", "--lifecycle-artifact", artifact, "--jobs", String(jobs)]
    }

    private func analyze(_ repository: URL, _ artifact: URL, jobs: Int = 2) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI(Self.arguments(repository.path, artifact.path, jobs: jobs))
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
