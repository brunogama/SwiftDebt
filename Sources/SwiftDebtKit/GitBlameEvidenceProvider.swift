import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle

struct GitBlameEvidenceProvider: Sendable {
    private let process: GitBlameProcess

    init(
        runner: any GitHistoryProcessRunning = GitHistorySubprocessRunner(),
        timeoutSeconds: TimeInterval = 10
    ) {
        self.process = GitBlameProcess(runner: runner, timeoutSeconds: timeoutSeconds)
    }

    func inspect(
        executablePath: String,
        capture: LifecycleAnalysisCapture,
        sources: [SourceUnit]
    ) -> GitBlameEvidenceAvailability {
        guard (executablePath as NSString).isAbsolutePath,
            FileManager.default.isExecutableFile(atPath: executablePath)
        else {
            return unavailable(
                "git-blame-provider-invalid",
                "The Git blame provider path must name an absolute executable file."
            )
        }
        guard
            case .available(let repositoryRoot, let capturedHead, let state, _, _, _, _) = capture.gitSnapshot
        else {
            return unavailable(
                "git-blame-repository-unavailable",
                "The Git blame provider requires a captured Git repository and HEAD."
            )
        }
        guard state == .clean else {
            return unavailable(
                "git-blame-working-tree-modified",
                "The Git blame provider requires the captured working tree to be clean."
            )
        }

        let executable = URL(fileURLWithPath: executablePath)
        let repository = URL(fileURLWithPath: repositoryRoot)
        do {
            try validateHead(capturedHead, executable: executable, repository: repository)
            try validateTrackedTree(executable: executable, repository: repository)
            let facts = try sources.map {
                try inspectSource(
                    $0,
                    capturedHead: capturedHead,
                    capture: capture,
                    executable: executable,
                    repository: repository
                )
            }
            try validateHead(capturedHead, executable: executable, repository: repository)
            try validateTrackedTree(executable: executable, repository: repository)
            return .available(try GitBlameEvidence(headRevision: capturedHead, sourceFacts: facts))
        } catch let failure as ProviderFailure {
            return unavailable(failure.code, failure.message)
        } catch {
            return unavailable(
                "git-blame-output-malformed",
                "The Git blame provider returned evidence that could not be canonicalized."
            )
        }
    }

    private func inspectSource(
        _ source: SourceUnit,
        capturedHead: GitRevisionID,
        capture: LifecycleAnalysisCapture,
        executable: URL,
        repository: URL
    ) throws -> GitBlameSourceFacts {
        let sourcePath = try SourcePath(source.path)
        let repositoryPath =
            capture.sourceSelection?.repositoryRelativeRoot.map {
                $0.rawValue + "/" + sourcePath.rawValue
            } ?? sourcePath.rawValue
        let committedSource = try process.require(
            ["-C", repository.path, "cat-file", "blob", "\(capturedHead.rawValue):\(repositoryPath)"],
            operation: "read committed source",
            executable: executable,
            repository: repository
        )
        guard committedSource == source.content else {
            throw ProviderFailure(
                code: "git-blame-source-mismatch",
                message: "The analyzed SourceUnit bytes do not match the captured Git HEAD."
            )
        }
        let output = try process.require(
            [
                "-C", repository.path,
                "blame", "--no-ignore-revs-file", "--line-porcelain",
                capturedHead.rawValue, "--", repositoryPath,
            ],
            operation: "blame source",
            executable: executable,
            repository: repository
        )
        let revisions: [GitRevisionID]
        do {
            revisions = try GitBlamePorcelainParser().parse(output, expectedSource: source.content)
        } catch {
            throw ProviderFailure(
                code: "git-blame-output-malformed",
                message: "The Git blame provider returned malformed or source-mismatched line evidence."
            )
        }
        for revision in Set(revisions).sorted(by: { $0.rawValue < $1.rawValue }) {
            let result = process.run(
                ["-C", repository.path, "merge-base", "--is-ancestor", revision.rawValue, capturedHead.rawValue],
                executable: executable,
                repository: repository
            )
            guard result.exitCode == 0, !result.timedOut else {
                throw ProviderFailure(
                    code: "git-blame-stale-evidence",
                    message: "The Git blame provider returned a line revision outside the captured HEAD ancestry."
                )
            }
        }
        return try GitBlameSourceFacts(
            sourcePath: sourcePath,
            headRevision: capturedHead,
            sourceContent: source.content,
            revisionsByLine: revisions
        )
    }

    private func validateHead(
        _ capturedHead: GitRevisionID,
        executable: URL,
        repository: URL
    ) throws {
        let value = try process.require(
            ["-C", repository.path, "rev-parse", "--verify", "HEAD^{commit}"],
            operation: "resolve HEAD",
            executable: executable,
            repository: repository
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == capturedHead.rawValue else {
            throw ProviderFailure(
                code: "git-blame-head-mismatch",
                message: "The Git blame provider HEAD does not match the captured analysis HEAD."
            )
        }
    }

    private func validateTrackedTree(executable: URL, repository: URL) throws {
        let output = try process.require(
            ["-C", repository.path, "status", "--porcelain=v1", "--untracked-files=no", "--", "."],
            operation: "inspect tracked working tree",
            executable: executable,
            repository: repository
        )
        guard output.isEmpty else {
            throw ProviderFailure(
                code: "git-blame-working-tree-modified",
                message: "Tracked files changed after the clean analysis capture."
            )
        }
    }

    private func unavailable(_ code: String, _ message: String) -> GitBlameEvidenceAvailability {
        guard let reason = try? LifecycleReason(code: code, message: message) else {
            preconditionFailure("Git blame availability reasons are valid lifecycle evidence.")
        }
        return .unavailable(reason)
    }
}
