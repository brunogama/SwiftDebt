import Foundation
import Testing

@testable import SwiftDebtKit

extension RepositorySyntaxCacheCLIWorkflowTests {
    @Test("Default cache remains local under a network-denied real CLI run")
    func defaultCacheUsesNoNetwork() throws {
        #if os(macOS)
            let fixture = try makeCacheFixture()
            var defaultCache: URL?
            defer {
                try? FileManager.default.removeItem(at: fixture.root)
                if let defaultCache { try? FileManager.default.removeItem(at: defaultCache) }
            }
            try initializeGitRepository(fixture.repository)
            let deniedEvidence = fixture.artifacts.appendingPathComponent("default-denied-evidence.json")
            let deniedActivity = fixture.artifacts.appendingPathComponent("default-denied-cache.json")
            let deniedArguments = [
                "analyze", fixture.repository.path, "--format", "json", "--jobs", "1",
                "--repository-evidence", deniedEvidence.path,
                "--repository-cache-report", deniedActivity.path,
            ]
            let denied = try runNetworkDeniedSwiftDebt(deniedArguments)
            let deniedReport = try JSONDecoder().decode(
                RepositorySyntaxCacheReport.self,
                from: Data(contentsOf: deniedActivity)
            )
            let location = try #require(deniedReport.storage.location)
            defaultCache = URL(fileURLWithPath: location)

            let warmEvidence = fixture.artifacts.appendingPathComponent("default-warm-evidence.json")
            let warmActivity = fixture.artifacts.appendingPathComponent("default-warm-cache.json")
            let warmArguments = [
                "analyze", fixture.repository.path, "--format", "json", "--jobs", "1",
                "--repository-evidence", warmEvidence.path,
                "--repository-cache-report", warmActivity.path,
            ]
            let warm = try runSwiftDebt(warmArguments)
            let warmReport = try JSONDecoder().decode(
                RepositorySyntaxCacheReport.self,
                from: Data(contentsOf: warmActivity)
            )

            #expect(denied.status == 0)
            #expect(denied.stderr.isEmpty)
            #expect(deniedReport.disposition == .coldRebuild)
            #expect(deniedReport.networkRequestCount == 0)
            #expect(warm.status == 0)
            #expect(warm.stdout == denied.stdout)
            #expect(try Data(contentsOf: warmEvidence) == Data(contentsOf: deniedEvidence))
            #expect(warmReport.disposition == .warmReuse)
            #expect(warmReport.storage.location == deniedReport.storage.location)
            #expect(try gitStatus(fixture.repository).isEmpty)
        #endif
    }

    private func runNetworkDeniedSwiftDebt(_ arguments: [String]) throws -> CLIRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments =
            [
                "-p", "(version 1)\n(allow default)\n(deny network*)",
                try swiftDebtExecutableURL().path,
            ] + arguments
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
            stdout: String(
                decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ),
            stderr: String(
                decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }
}
