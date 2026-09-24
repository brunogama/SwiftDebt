import Foundation

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

func runSwiftDebt(_ arguments: [String], currentDirectory: URL? = nil) throws -> CLIRunResult {
    let process = Process()
    process.executableURL = try swiftDebtExecutableURL()
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory ?? repositoryRoot
    process.environment = ProcessInfo.processInfo.environment.merging([
        "CI": "1",
        "TERM": "dumb",
    ]) { _, new in new }
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return CLIRunResult(
        status: process.terminationStatus,
        stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
}

private func swiftDebtExecutableURL() throws -> URL {
    let direct = repositoryRoot.appendingPathComponent(".build/debug/swift-debt")
    if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
    let build = repositoryRoot.appendingPathComponent(".build")
    guard let enumerator = FileManager.default.enumerator(at: build, includingPropertiesForKeys: nil) else {
        throw CLIWorkflowTestError(message: "Missing .build directory")
    }
    let matches = enumerator.compactMap { item -> URL? in
        guard let url = item as? URL, url.lastPathComponent == "swift-debt", url.path.contains("/debug/") else {
            return nil
        }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }.sorted { lhs, rhs in
        if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
        return lhs.path < rhs.path
    }
    guard let match = matches.first else {
        throw CLIWorkflowTestError(message: "Could not locate built swift-debt executable")
    }
    return match
}

struct CLIRunResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

private struct CLIWorkflowTestError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
