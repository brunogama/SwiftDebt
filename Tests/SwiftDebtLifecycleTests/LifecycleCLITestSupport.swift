import Foundation
import SwiftDebtLifecycle

struct LifecycleCLIRunResult: Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

func runLifecycleCLIWithFileSizeLimit(_ arguments: [String]) throws -> LifecycleCLIRunResult {
    let executable = try lifecycleExecutableURL()
    let result = try runLifecycleProcess(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: [
            "-c", "trap '' XFSZ; ulimit -f 1; exec \"$@\"",
            "swift-debt", executable.path,
        ] + arguments,
        directory: repositoryRoot
    )
    return LifecycleCLIRunResult(
        status: result.status,
        standardOutput: result.standardOutput,
        standardError: result.standardError
    )
}

func runLifecycleCLI(
    _ arguments: [String], environment: [String: String]? = nil
) throws -> LifecycleCLIRunResult {
    let result = try runLifecycleProcess(
        executable: lifecycleExecutableURL(),
        arguments: arguments,
        directory: repositoryRoot,
        environment: environment
    )
    return LifecycleCLIRunResult(
        status: result.status,
        standardOutput: result.standardOutput,
        standardError: result.standardError
    )
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

func lifecycleExecutableURL() throws -> URL {
    #if DEBUG
        let configuration = "debug"
    #else
        let configuration = "release"
    #endif
    let direct = repositoryRoot.appendingPathComponent(".build/\(configuration)/swift-debt")
    if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
    let build = repositoryRoot.appendingPathComponent(".build")
    guard let enumerator = FileManager.default.enumerator(at: build, includingPropertiesForKeys: nil) else {
        throw LifecycleStoreError.missingArtifact("Built swift-debt executable")
    }
    let matches = enumerator.compactMap { item -> URL? in
        guard let url = item as? URL,
            url.lastPathComponent == "swift-debt",
            url.path.contains("/\(configuration)/"),
            FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url
    }.sorted { $0.path.count == $1.path.count ? $0.path < $1.path : $0.path.count < $1.path.count }
    guard let match = matches.first else {
        throw LifecycleStoreError.missingArtifact("Built swift-debt executable")
    }
    return match
}
