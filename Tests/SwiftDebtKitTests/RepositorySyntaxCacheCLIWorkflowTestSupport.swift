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

    func cacheSwiftDebtExecutableURL() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let direct = root.appendingPathComponent(".build/debug/swift-debt")
        if FileManager.default.isExecutableFile(atPath: direct.path) { return direct }
        let build = root.appendingPathComponent(".build")
        guard
            let enumerator = FileManager.default.enumerator(
                at: build,
                includingPropertiesForKeys: nil
            )
        else {
            throw CacheCLITestError("Missing .build directory")
        }
        let matches = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                url.lastPathComponent == "swift-debt",
                url.path.contains("/debug/"),
                FileManager.default.isExecutableFile(atPath: url.path)
            else { return nil }
            return url
        }.sorted { lhs, rhs in
            if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
            return lhs.path < rhs.path
        }
        guard let match = matches.first else {
            throw CacheCLITestError("Could not locate built swift-debt executable")
        }
        return match
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
