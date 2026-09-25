import Foundation

struct CacheCLIFixture {
    let root: URL
    let repository: URL
    let artifacts: URL
    let evidence: URL
    let cache: URL
    let activity: URL
}

extension RepositorySyntaxCacheCLIWorkflowTests {
    func makeCacheFixture() throws -> CacheCLIFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swiftdebt-cache-cli-\(UUID().uuidString)",
            isDirectory: true
        )
        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let artifacts = root.appendingPathComponent("artifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: repositoryFixtureRoot.appendingPathComponent("Positive"),
            to: repository
        )
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        return CacheCLIFixture(
            root: root,
            repository: repository,
            artifacts: artifacts,
            evidence: artifacts.appendingPathComponent("repository-evidence.json"),
            cache: artifacts.appendingPathComponent("repository-facts.json"),
            activity: artifacts.appendingPathComponent("repository-cache-report.json")
        )
    }

    func initializeGitRepository(_ repository: URL) throws {
        try runGitFixture(["init"], root: repository)
        try runGitFixture(["config", "user.name", "Cache Test"], root: repository)
        try runGitFixture(["config", "user.email", "cache@example.test"], root: repository)
        try runGitFixture(["add", "."], root: repository)
        try runGitFixture(["commit", "-m", "fixture"], root: repository)
    }

    func gitStatus(_ repository: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", repository.path, "status", "--porcelain"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0 else {
            throw CacheCLITestError("git status failed: \(diagnostic)")
        }
        return String(
            decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
    }

    var repositoryFixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RepositoryAnalysis")
    }
}

private struct CacheCLITestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
