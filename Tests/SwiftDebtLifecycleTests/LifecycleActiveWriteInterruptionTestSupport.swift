import Foundation
import Testing

#if os(macOS)
    import Darwin

    enum WriteInterruptionBoundary {
        case temporaryByteWrite
        case atomicRename

        var markerEnvironmentKey: String {
            switch self {
            case .temporaryByteWrite: "SWIFTDEBT_AT22_WRITE_MARKER"
            case .atomicRename: "SWIFTDEBT_AT22_RENAME_MARKER"
            }
        }
    }

    struct ByteWriteProgress {
        let path: String
        let temporaryByteCount: Int
        let writtenByteCount: Int
        let requestedByteCount: Int
    }

    func compileLifecycleWriteInterposer(in directory: URL) throws -> URL {
        let interposer = directory.appendingPathComponent("atomic-write.dylib")
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LifecycleAtomicRenameInterposer.c")
        let compilation = try runLifecycleProcess(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: [
                "clang", "-arch", "x86_64", "-arch", "arm64", "-arch", "arm64e",
                "-dynamiclib", source.path, "-o", interposer.path,
            ],
            directory: directory
        )
        #expect(compilation.status == 0, "\(compilation.standardError)")
        return interposer
    }

    func startPausedLifecycleWrite(
        repository: URL,
        artifact: URL,
        interposer: URL,
        marker: URL,
        boundary: WriteInterruptionBoundary,
        errorOutput: FileHandle
    ) throws -> Process {
        let process = Process()
        process.executableURL = try lifecycleExecutableURL()
        process.arguments =
            ["analyze", repository.path, "--format", "json"]
            + ["--lifecycle-artifact", artifact.path]
        var environment = ProcessInfo.processInfo.environment
        environment["DYLD_INSERT_LIBRARIES"] = interposer.path
        environment["SWIFTDEBT_AT22_ARTIFACT_NAME"] = artifact.lastPathComponent
        environment[boundary.markerEnvironmentKey] = marker.path
        if boundary == .temporaryByteWrite {
            environment["SWIFTDEBT_AT22_ARTIFACT_PATH"] = artifact.path
        }
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorOutput
        try process.run()
        return process
    }

    func awaitLifecycleRename(
        marker: URL, process: Process, errorOutput: FileHandle, errorURL: URL
    ) throws -> String {
        try awaitLifecycleWriteInterruption(
            marker: marker, process: process,
            errorOutput: errorOutput, errorURL: errorURL,
            pendingDescription: "atomic rename"
        )
    }

    func awaitLifecycleByteWrite(
        marker: URL, process: Process, errorOutput: FileHandle, errorURL: URL
    ) throws -> ByteWriteProgress {
        let markerText = try awaitLifecycleWriteInterruption(
            marker: marker, process: process,
            errorOutput: errorOutput, errorURL: errorURL,
            pendingDescription: "temporary artifact byte write"
        )
        let fields = markerText.split(separator: "\n", omittingEmptySubsequences: false)
        guard fields.count == 4,
            let temporaryByteCount = Int(fields[1]),
            let writtenByteCount = Int(fields[2]),
            let requestedByteCount = Int(fields[3])
        else {
            throw NSError(
                domain: "LifecycleActiveWriteInterruption", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid byte-write marker: \(markerText)"]
            )
        }
        return ByteWriteProgress(
            path: String(fields[0]),
            temporaryByteCount: temporaryByteCount,
            writtenByteCount: writtenByteCount,
            requestedByteCount: requestedByteCount
        )
    }

    private func awaitLifecycleWriteInterruption(
        marker: URL,
        process: Process,
        errorOutput: FileHandle,
        errorURL: URL,
        pendingDescription: String
    ) throws -> String {
        // This bounds a deadlocked child, not normal analysis progress under coverage contention.
        let watchdog = Date().addingTimeInterval(300)
        while !FileManager.default.fileExists(atPath: marker.path) && process.isRunning {
            if Date() >= watchdog {
                _ = kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
                throw try lifecycleWriteInterruptionFailure(
                    "CLI did not reach \(pendingDescription) within five minutes",
                    process: process, errorOutput: errorOutput, errorURL: errorURL
                )
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard FileManager.default.fileExists(atPath: marker.path) else {
            process.waitUntilExit()
            throw try lifecycleWriteInterruptionFailure(
                "CLI exited before \(pendingDescription)",
                process: process, errorOutput: errorOutput, errorURL: errorURL
            )
        }
        return try String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lifecycleWriteInterruptionFailure(
        _ reason: String, process: Process, errorOutput: FileHandle, errorURL: URL
    ) throws -> NSError {
        try errorOutput.synchronize()
        let errorData = try Data(contentsOf: errorURL)
        let errorText = String(bytes: errorData, encoding: .utf8) ?? "<invalid UTF-8>"
        let detail = "\(reason); status \(process.terminationStatus); stderr: \(errorText)"
        return NSError(
            domain: "LifecycleActiveWriteInterruption", code: Int(process.terminationStatus),
            userInfo: [NSLocalizedDescriptionKey: detail]
        )
    }
#endif
