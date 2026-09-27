import Foundation
import SwiftDebtLifecycle
import Testing

#if os(macOS)
    import Darwin

    @Suite("R3 active artifact write interruption")
    struct LifecycleActiveWriteInterruptionTests {
        @Test("SIGKILL during temporary artifact byte writes preserves prior state and retry")
        func killedTemporaryByteWriteFailsClosedAndCanRetry() throws {
            let fixture = try TemporaryLifecycleGitRepository()
            let openingRevision = try fixture.commit(source: detectedSource, message: "add forced try")
            let resolvedRevision = try fixture.commit(source: resolvedSource, message: "remove forced try")
            let expectedArtifact = fixture.directory.appendingPathComponent("expected.json")
            let interruptedArtifact = fixture.directory.appendingPathComponent("interrupted.json")

            try fixture.runGit(["checkout", openingRevision])
            #expect(try analyze(fixture.repository, expectedArtifact).status == 0)
            #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
            let priorBytes = try Data(contentsOf: interruptedArtifact)
            let priorPermissions = try #require(
                try FileManager.default.attributesOfItem(atPath: interruptedArtifact.path)[
                    .posixPermissions
                ] as? NSNumber
            ).uint16Value

            try fixture.runGit(["checkout", resolvedRevision])
            #expect(try analyze(fixture.repository, expectedArtifact).status == 0)
            let expectedBytes = try Data(contentsOf: expectedArtifact)

            let interposer = try compileLifecycleWriteInterposer(in: fixture.directory)
            let captureDirectory = fixture.directory.appendingPathComponent("byte-write-capture")
            try FileManager.default.createDirectory(
                at: captureDirectory, withIntermediateDirectories: true
            )
            let marker = captureDirectory.appendingPathComponent("marker")
            let errorURL = captureDirectory.appendingPathComponent("stderr")
            _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
            let errorOutput = try FileHandle(forWritingTo: errorURL)
            defer { try? errorOutput.close() }
            let process = try startPausedLifecycleWrite(
                repository: fixture.repository, artifact: interruptedArtifact,
                interposer: interposer, marker: marker, boundary: .temporaryByteWrite,
                errorOutput: errorOutput
            )
            defer {
                if process.isRunning {
                    _ = kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }

            let progress = try awaitLifecycleByteWrite(
                marker: marker, process: process,
                errorOutput: errorOutput, errorURL: errorURL
            )
            #expect(try Data(contentsOf: marker).last == 0x0A)
            #expect(!FileManager.default.fileExists(atPath: marker.path + ".pending"))
            let temporaryArtifact = URL(fileURLWithPath: progress.path)
            // Foundation keeps its in-progress sibling unreadable. The child is stopped, so grant
            // owner access only to that sibling for exact on-disk prefix inspection.
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: temporaryArtifact.path
            )
            let partialBytes = try Data(contentsOf: temporaryArtifact)
            #expect(progress.temporaryByteCount > 0)
            #expect(progress.temporaryByteCount < expectedBytes.count)
            #expect(progress.writtenByteCount > 0)
            #expect(progress.writtenByteCount < progress.requestedByteCount)
            #expect(partialBytes.count == progress.temporaryByteCount)
            #expect(expectedBytes.starts(with: partialBytes))
            #expect(try Data(contentsOf: interruptedArtifact) == priorBytes)
            #expect(process.isRunning)

            _ = kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            #expect(process.terminationReason == .uncaughtSignal)
            #expect(try Data(contentsOf: interruptedArtifact) == priorBytes)
            let preservedPermissions = try #require(
                try FileManager.default.attributesOfItem(atPath: interruptedArtifact.path)[
                    .posixPermissions
                ] as? NSNumber
            ).uint16Value
            #expect(preservedPermissions == priorPermissions)
            #expect(try LifecycleArtifactStore(artifactURL: interruptedArtifact).load().snapshots.count == 1)

            let rejectedTemporary = try runLifecycleCLI([
                "lifecycle", "inventory", temporaryArtifact.path, "--format", "json",
            ])
            #expect(rejectedTemporary.status == 2)
            #expect(rejectedTemporary.standardOutput.isEmpty)
            #expect(rejectedTemporary.standardError.contains("Unable to read lifecycle artifact"))

            #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
            #expect(try Data(contentsOf: interruptedArtifact) == expectedBytes)
            #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
            #expect(try Data(contentsOf: interruptedArtifact) == expectedBytes)
        }

        @Test("SIGKILL before atomic replacement preserves the prior artifact and retry")
        func killedActiveWriteCanRetry() throws {
            let fixture = try TemporaryLifecycleGitRepository()
            let openingRevision = try fixture.commit(source: detectedSource, message: "add forced try")
            let resolvedRevision = try fixture.commit(source: resolvedSource, message: "remove forced try")
            let expectedArtifact = fixture.directory.appendingPathComponent("expected.json")
            let interruptedArtifact = fixture.directory.appendingPathComponent("interrupted.json")

            try fixture.runGit(["checkout", openingRevision])
            #expect(try analyze(fixture.repository, expectedArtifact).status == 0)
            #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
            let priorBytes = try Data(contentsOf: interruptedArtifact)

            try fixture.runGit(["checkout", resolvedRevision])
            #expect(try analyze(fixture.repository, expectedArtifact).status == 0)
            let expectedBytes = try Data(contentsOf: expectedArtifact)

            let interposer = try compileLifecycleWriteInterposer(in: fixture.directory)
            let marker = fixture.directory.appendingPathComponent("atomic-rename-marker")
            let errorURL = fixture.directory.appendingPathComponent("interrupted-stderr")
            _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
            let errorOutput = try FileHandle(forWritingTo: errorURL)
            defer { try? errorOutput.close() }
            let process = try startPausedLifecycleWrite(
                repository: fixture.repository, artifact: interruptedArtifact,
                interposer: interposer, marker: marker, boundary: .atomicRename,
                errorOutput: errorOutput
            )
            defer {
                if process.isRunning {
                    _ = kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }

            let temporaryName = try awaitLifecycleRename(
                marker: marker, process: process,
                errorOutput: errorOutput, errorURL: errorURL
            )
            let markerData = try Data(contentsOf: marker)
            #expect(markerData.last == 0x0A)
            #expect(String(bytes: markerData, encoding: .utf8) == temporaryName + "\n")
            #expect(!FileManager.default.fileExists(atPath: marker.path + ".pending"))
            let temporaryArtifact = interruptedArtifact.deletingLastPathComponent()
                .appendingPathComponent(temporaryName)
            #expect(try Data(contentsOf: temporaryArtifact) == expectedBytes)
            #expect(try Data(contentsOf: interruptedArtifact) == priorBytes)
            #expect(process.isRunning)
            _ = kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            #expect(process.terminationReason == .uncaughtSignal)
            #expect(try Data(contentsOf: interruptedArtifact) == priorBytes)
            #expect(try LifecycleArtifactStore(artifactURL: interruptedArtifact).load().snapshots.count == 1)

            #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
            #expect(try Data(contentsOf: interruptedArtifact) == expectedBytes)
            #expect(try analyze(fixture.repository, interruptedArtifact).status == 0)
            #expect(try Data(contentsOf: interruptedArtifact) == expectedBytes)
        }

        private func analyze(_ repository: URL, _ artifact: URL) throws -> LifecycleCLIRunResult {
            try runLifecycleCLI(
                ["analyze", repository.path, "--format", "json"]
                    + ["--lifecycle-artifact", artifact.path]
            )
        }

        private let detectedSource = """
            func load() throws -> Int { 1 }
            func run() { _ = try! load() }
            """

        private let resolvedSource = """
            func load() throws -> Int { 1 }
            func run() { _ = try? load() }
            """
    }

#endif
