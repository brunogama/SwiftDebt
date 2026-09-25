import Foundation
import SwiftDebtCore

struct RepositoryVersionControlInspector {
    private let runner: any GitHistoryProcessRunning

    init(runner: any GitHistoryProcessRunning = GitHistorySubprocessRunner()) {
        self.runner = runner
    }

    func identity(at root: URL, excluding generatedPaths: [URL] = []) -> RepositoryVersionControlIdentity? {
        let revision = runGit(["rev-parse", "--verify", "HEAD"], root: root)
        guard revision.exitCode == 0, !revision.timedOut else { return nil }
        let value = revision.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        var statusArguments = ["status", "--porcelain=v1", "--untracked-files=normal"]
        if !generatedPaths.isEmpty {
            let topLevel = runGit(["rev-parse", "--show-toplevel"], root: root)
            guard topLevel.exitCode == 0, !topLevel.timedOut else { return nil }
            let repositoryRoot = URL(
                fileURLWithPath: topLevel.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
                isDirectory: true
            )
            let exclusions = generatedPaths.compactMap { path -> String? in
                guard isWithin(path, root: repositoryRoot) else { return nil }
                return relativePath(path, root: repositoryRoot)
            }
            if !exclusions.isEmpty {
                statusArguments += ["--", ":(top,glob)**"]
                statusArguments += exclusions.sorted().map { ":(top,exclude,literal)\($0)" }
            }
        }
        let status = runGit(statusArguments, root: root)
        guard status.exitCode == 0, !status.timedOut else { return nil }
        return try? RepositoryVersionControlIdentity(
            revision: value,
            workingTreeState: status.stdout.isEmpty ? .clean : .modified
        )
    }

    private func runGit(_ arguments: [String], root: URL) -> GitHistoryProcessResult {
        runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", root.path] + arguments,
            workingDirectory: root,
            timeoutSeconds: 5
        )
    }
}
