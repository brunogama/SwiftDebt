import Foundation
import SwiftDebtLifecycle

enum LifecycleGitSnapshot: Equatable, Sendable {
    case available(
        repositoryRoot: String,
        revision: GitRevisionID,
        workingTreeState: SourceWorkingTreeState,
        parentRevisions: [GitRevisionID],
        statusDigest: String
    )
    case unavailable

    func sourceIdentity(contentDigest: LifecycleDigest) -> SnapshotSourceIdentity {
        switch self {
        case .available(_, let revision, let state, _, _):
            .git(revision: revision, workingTreeState: state, contentDigest: contentDigest)
        case .unavailable:
            .contentDigest(contentDigest)
        }
    }
}

struct LifecycleGitSnapshotProvider: Sendable {
    private let runner: any GitHistoryProcessRunning
    private let timeoutSeconds: TimeInterval

    init(
        runner: any GitHistoryProcessRunning = GitHistorySubprocessRunner(),
        timeoutSeconds: TimeInterval = 5
    ) {
        self.runner = runner
        self.timeoutSeconds = timeoutSeconds
    }

    func capture(root: URL, excludingGeneratedOutputs outputURLs: [URL]) throws -> LifecycleGitSnapshot {
        let topLevel = run(["rev-parse", "--show-toplevel"], root: root)
        guard topLevel.exitCode == 0, !topLevel.timedOut else {
            if !topLevel.timedOut, topLevel.exitCode == 128,
                topLevel.stderr.contains("not a git repository")
            {
                return .unavailable
            }
            throw LifecycleAnalysisError.gitInspectionFailed(diagnosticText(topLevel))
        }
        let repositoryRoot = topLevel.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryRoot.isEmpty else {
            throw LifecycleAnalysisError.gitInspectionFailed("Git returned an empty repository root.")
        }
        let repositoryURL = URL(fileURLWithPath: repositoryRoot).standardizedFileURL.resolvingSymlinksInPath()

        let revisionResult = try require(["rev-parse", "--verify", "HEAD^{commit}"], root: repositoryURL)
        let revision = try GitRevisionID(revisionResult.trimmingCharacters(in: .whitespacesAndNewlines))
        let parentResult = try require(["show", "-s", "--format=%P", "HEAD"], root: repositoryURL)
        let parents = try parentResult.split(whereSeparator: { $0.isWhitespace }).map {
            try GitRevisionID(String($0))
        }
        let statusArguments = try statusArguments(
            excluding: outputURLs,
            repositoryRoot: repositoryURL
        )
        let status = try require(statusArguments, root: repositoryURL)
        return .available(
            repositoryRoot: repositoryURL.path,
            revision: revision,
            workingTreeState: status.isEmpty ? .clean : .modified,
            parentRevisions: parents,
            statusDigest: LifecycleSHA256.hexDigest(Data(status.utf8))
        )
    }

    private func statusArguments(excluding outputURLs: [URL], repositoryRoot: URL) throws -> [String] {
        var arguments = ["status", "--porcelain=v1", "--untracked-files=all", "--", "."]
        let relativeOutputs = Set(
            outputURLs.compactMap { outputURL -> String? in
                let output = outputURL.standardizedFileURL.resolvingSymlinksInPath()
                guard output.path != repositoryRoot.path, isWithin(output, root: repositoryRoot) else { return nil }
                return relativePath(output, root: repositoryRoot)
            }
        ).sorted()
        for relativeOutput in relativeOutputs {
            let tracked = try require(
                ["ls-files", "-z", "--", ":(top,literal)\(relativeOutput)"],
                root: repositoryRoot
            )
            if tracked.isEmpty {
                arguments.append(":(top,literal,exclude)\(relativeOutput)")
            }
        }
        return arguments
    }

    private func require(_ arguments: [String], root: URL) throws -> String {
        let result = run(arguments, root: root)
        guard result.exitCode == 0, !result.timedOut else {
            throw LifecycleAnalysisError.gitInspectionFailed(diagnosticText(result))
        }
        return result.stdout
    }

    private func run(_ arguments: [String], root: URL) -> GitHistoryProcessResult {
        runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", root.path] + arguments,
            workingDirectory: root,
            timeoutSeconds: timeoutSeconds
        )
    }
}
