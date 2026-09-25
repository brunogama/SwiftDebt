import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

struct LifecycleProcessResult {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

enum LifecycleProcessFailure: Error {
    case timedOut([String])
    case couldNotReap([String])
}

func runLifecycleProcess(
    executable: URL,
    arguments: [String],
    directory: URL,
    environment: [String: String]? = nil,
    mergeStandardError: Bool = false,
    timeout: TimeInterval = 30
) throws -> LifecycleProcessResult {
    let captureDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swift-debt-process-\(UUID().uuidString)", isDirectory: true
    )
    try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
    var removeCaptureDirectory = true
    defer {
        if removeCaptureDirectory { try? FileManager.default.removeItem(at: captureDirectory) }
    }

    let outputURL = captureDirectory.appendingPathComponent("stdout")
    let errorURL = captureDirectory.appendingPathComponent("stderr")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    let errors = try FileHandle(forWritingTo: errorURL)
    defer {
        try? output.close()
        try? errors.close()
    }

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = environment
    process.standardOutput = output
    process.standardError = mergeStandardError ? output : errors
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    try process.run()
    if finished.wait(timeout: .now() + timeout) == .timedOut {
        if process.isRunning { process.terminate() }
        if finished.wait(timeout: .now() + 2) == .timedOut {
            if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            if finished.wait(timeout: .now() + 5) == .timedOut {
                removeCaptureDirectory = false
                throw LifecycleProcessFailure.couldNotReap(arguments)
            }
        }
        process.waitUntilExit()
        throw LifecycleProcessFailure.timedOut(arguments)
    }
    process.waitUntilExit()
    try output.synchronize()
    try errors.synchronize()
    return LifecycleProcessResult(
        status: process.terminationStatus,
        standardOutput: String(decoding: try Data(contentsOf: outputURL), as: UTF8.self),
        standardError: mergeStandardError
            ? "" : String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
    )
}
