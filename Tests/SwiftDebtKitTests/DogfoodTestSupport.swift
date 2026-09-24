import Foundation

let dogfoodRepositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

struct DogfoodCLIRunResult {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var standardError: String {
        String(decoding: stderr, as: UTF8.self)
    }
}

func runDogfoodSwiftDebt(_ arguments: [String]) throws -> DogfoodCLIRunResult {
    let captureDirectory = try makeDogfoodTemporaryDirectory(named: "process")
    defer { try? FileManager.default.removeItem(at: captureDirectory) }

    let stdoutURL = captureDirectory.appendingPathComponent("stdout")
    let stderrURL = captureDirectory.appendingPathComponent("stderr")
    try Data().write(to: stdoutURL)
    try Data().write(to: stderrURL)

    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    let process = Process()
    process.executableURL = try dogfoodSwiftDebtExecutableURL()
    process.arguments = arguments
    process.currentDirectoryURL = dogfoodRepositoryRoot
    process.environment = ProcessInfo.processInfo.environment.merging(
        [
            "CI": "1",
            "LANG": "C",
            "LC_ALL": "C",
            "NO_COLOR": "1",
            "TERM": "dumb",
        ],
        uniquingKeysWith: { _, new in new }
    )
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle

    do {
        try process.run()
        process.waitUntilExit()
        try stdoutHandle.close()
        try stderrHandle.close()
    } catch {
        try? stdoutHandle.close()
        try? stderrHandle.close()
        throw error
    }

    return try DogfoodCLIRunResult(
        status: process.terminationStatus,
        stdout: Data(contentsOf: stdoutURL),
        stderr: Data(contentsOf: stderrURL)
    )
}

func makeDogfoodTemporaryDirectory(named name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftdebt-dogfood-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func dogfoodSwiftDebtExecutableURL() throws -> URL {
    let direct = dogfoodRepositoryRoot.appendingPathComponent(".build/debug/swift-debt")
    if FileManager.default.isExecutableFile(atPath: direct.path) {
        return direct
    }

    let buildDirectory = dogfoodRepositoryRoot.appendingPathComponent(".build")
    guard
        let enumerator = FileManager.default.enumerator(
            at: buildDirectory,
            includingPropertiesForKeys: [.isExecutableKey]
        )
    else {
        throw DogfoodTestError("Missing .build directory")
    }

    let matches = enumerator.compactMap { item -> URL? in
        guard
            let url = item as? URL,
            url.lastPathComponent == "swift-debt",
            url.path.contains("/debug/"),
            FileManager.default.isExecutableFile(atPath: url.path)
        else {
            return nil
        }
        return url
    }.sorted { $0.path < $1.path }

    guard let executable = matches.first else {
        throw DogfoodTestError("Could not locate built swift-debt executable")
    }
    return executable
}

private struct DogfoodTestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
