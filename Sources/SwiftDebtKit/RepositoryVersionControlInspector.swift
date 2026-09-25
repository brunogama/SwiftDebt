import Foundation
import SwiftDebtCore

struct RepositoryVersionControlInspector {
    private let runner: any GitHistoryProcessRunning

    init(runner: any GitHistoryProcessRunning = GitHistorySubprocessRunner()) {
        self.runner = runner
    }

    func identity(at root: URL) -> RepositoryVersionControlIdentity? {
        let revision = runGit(["rev-parse", "--verify", "HEAD"], root: root)
        guard revision.exitCode == 0, !revision.timedOut else { return nil }
        let value = revision.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let status = runGit(["status", "--porcelain=v1", "--untracked-files=normal"], root: root)
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
