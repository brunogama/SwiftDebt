import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax

extension LifecycleIntroductionService {
    func isShallow(_ repositoryURL: URL) throws -> Bool {
        let output = try requireGit(["rev-parse", "--is-shallow-repository"], repositoryURL: repositoryURL)
        switch output.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": return true
        case "false": return false
        default:
            throw LifecycleAnalysisError.gitInspectionFailed("Git returned an invalid shallow-repository state")
        }
    }

    func gitRevision(of snapshot: ObservationSnapshot) -> GitRevisionID? {
        guard case .git(let revision, _, _) = snapshot.provenance.sourceIdentity else { return nil }
        return revision
    }

    func requireGit(_ arguments: [String], repositoryURL: URL) throws -> String {
        let result = runGit(arguments, repositoryURL: repositoryURL)
        guard result.exitCode == 0, !result.timedOut else {
            throw LifecycleAnalysisError.gitInspectionFailed(diagnosticText(result))
        }
        return result.stdout
    }

    func runGit(_ arguments: [String], repositoryURL: URL) -> GitHistoryProcessResult {
        runner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["git", "-C", repositoryURL.path] + arguments,
            workingDirectory: repositoryURL,
            timeoutSeconds: timeoutSeconds
        )
    }

    func require(executable: String, arguments: [String], directory: URL) throws {
        let result = runner.run(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            workingDirectory: directory,
            timeoutSeconds: timeoutSeconds
        )
        guard result.exitCode == 0, !result.timedOut else {
            throw LifecycleAnalysisError.gitInspectionFailed(diagnosticText(result))
        }
    }

    func reason(code: String, message: String) throws -> LifecycleReason {
        let normalized = message.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return try LifecycleReason(
            code: code,
            message: normalized.isEmpty ? "Historical evidence was unavailable." : normalized
        )
    }
}
