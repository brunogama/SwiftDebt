import Foundation
import SwiftDebtLifecycle

struct LifecycleCLIRunResult {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

func runLifecycleCLI(_ arguments: [String]) throws -> LifecycleCLIRunResult {
    let process = Process()
    process.executableURL = try lifecycleExecutableURL()
    process.arguments = arguments
    process.currentDirectoryURL = repositoryRoot
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError
    try process.run()
    process.waitUntilExit()
    return LifecycleCLIRunResult(
        status: process.terminationStatus,
        standardOutput: String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
        standardError: String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    )
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func lifecycleExecutableURL() throws -> URL {
    let direct = repositoryRoot.appendingPathComponent(".build/debug/swift-debt")
    if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
    let build = repositoryRoot.appendingPathComponent(".build")
    guard let enumerator = FileManager.default.enumerator(at: build, includingPropertiesForKeys: nil) else {
        throw LifecycleStoreError.missingArtifact("Built swift-debt executable")
    }
    let matches = enumerator.compactMap { item -> URL? in
        guard let url = item as? URL,
            url.lastPathComponent == "swift-debt",
            url.path.contains("/debug/"),
            FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url
    }.sorted { $0.path.count == $1.path.count ? $0.path < $1.path : $0.path.count < $1.path.count }
    guard let match = matches.first else {
        throw LifecycleStoreError.missingArtifact("Built swift-debt executable")
    }
    return match
}
