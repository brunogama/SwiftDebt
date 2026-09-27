import Foundation
import SwiftDebtLifecycle
import Testing

#if os(macOS)
    import Darwin

    @Suite("R3 active artifact write interruption")
    struct LifecycleActiveWriteInterruptionTests {
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

            let interposer = try compileInterposer(in: fixture.directory)
            let marker = fixture.directory.appendingPathComponent("atomic-rename-marker")
            let process = try startPausedWrite(
                repository: fixture.repository, artifact: interruptedArtifact,
                interposer: interposer, marker: marker
            )
            defer {
                if process.isRunning {
                    _ = kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }

            let deadline = Date().addingTimeInterval(15)
            while !FileManager.default.fileExists(atPath: marker.path) && process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            #expect(FileManager.default.fileExists(atPath: marker.path))
            guard FileManager.default.fileExists(atPath: marker.path) else { return }
            let temporaryName = try String(contentsOf: marker, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

        private func compileInterposer(in directory: URL) throws -> URL {
            let interposer = directory.appendingPathComponent("atomic-rename.dylib")
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/LifecycleAtomicRenameInterposer.c")
            let compilation = try runLifecycleProcess(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["clang", "-dynamiclib", source.path, "-o", interposer.path],
                directory: directory
            )
            #expect(compilation.status == 0, "\(compilation.standardError)")
            return interposer
        }

        private func startPausedWrite(
            repository: URL, artifact: URL, interposer: URL, marker: URL
        ) throws -> Process {
            let process = Process()
            process.executableURL = try lifecycleExecutableURL()
            process.arguments =
                ["analyze", repository.path, "--format", "json"]
                + ["--lifecycle-artifact", artifact.path]
            var environment = ProcessInfo.processInfo.environment
            environment["DYLD_INSERT_LIBRARIES"] = interposer.path
            environment["SWIFTDEBT_AT22_ARTIFACT_NAME"] = artifact.lastPathComponent
            environment["SWIFTDEBT_AT22_RENAME_MARKER"] = marker.path
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
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
