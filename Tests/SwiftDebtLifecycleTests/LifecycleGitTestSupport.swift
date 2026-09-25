import Foundation

final class TemporaryLifecycleGitRepository {
    let directory: URL
    let repository: URL
    let artifact: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-debt-lifecycle-git-\(UUID().uuidString)",
            isDirectory: true
        )
        repository = directory.appendingPathComponent("repository", isDirectory: true)
        artifact = repository.appendingPathComponent(".swift-debt/lifecycle.json")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try runGit(["init"])
        try runGit(["config", "user.name", "Lifecycle Test"])
        try runGit(["config", "user.email", "lifecycle@example.test"])
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func commit(source: String, message: String) throws -> String {
        try write(source: source)
        try runGit(["add", "Sources/Input.swift"])
        try runGit(["commit", "-m", message])
        return try gitOutput(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func commitAll(message: String) throws -> String {
        try runGit(["add", "-A"])
        try runGit(["commit", "-m", message])
        return try gitOutput(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func write(source: String) throws {
        try writeFile(relativePath: "Sources/Input.swift", content: source)
    }

    func writeFile(relativePath: String, content: String) throws {
        let fileURL = repository.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func removeFile(relativePath: String) throws {
        try FileManager.default.removeItem(at: repository.appendingPathComponent(relativePath))
    }

    func runGit(_ arguments: [String]) throws {
        _ = try gitOutput(arguments)
    }

    func gitOutput(_ arguments: [String]) throws -> String {
        let result = try runLifecycleProcess(
            executable: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", repository.path] + arguments,
            directory: repository,
            mergeStandardError: true
        )
        guard result.status == 0 else {
            throw LifecycleGitFixtureError(message: result.standardOutput)
        }
        return result.standardOutput
    }
}

private struct LifecycleGitFixtureError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
