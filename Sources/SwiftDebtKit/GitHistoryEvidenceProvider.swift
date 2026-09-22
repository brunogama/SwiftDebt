import Foundation
import SwiftDebtCore

public struct GitHistoryEvidenceRequest: Sendable {
    public let repositoryRoot: String
    public let referenceTime: Date
    public let entities: [DebtEntity]

    public init(repositoryRoot: String, referenceTime: Date, entities: [DebtEntity]) {
        self.repositoryRoot = repositoryRoot
        self.referenceTime = referenceTime
        self.entities = entities
    }
}

public struct GitHistoryEvidenceDiagnostic: Equatable, Sendable {
    public enum Severity: String, Sendable { case warning }

    public let severity: Severity
    public let message: String

    public init(severity: Severity = .warning, message: String) {
        self.severity = severity
        self.message = message
    }
}

public struct GitHistoryEvidenceResult: Equatable, Sendable {
    public let evidence: [DebtEvidence]
    public let diagnostics: [GitHistoryEvidenceDiagnostic]

    public init(evidence: [DebtEvidence], diagnostics: [GitHistoryEvidenceDiagnostic] = []) {
        self.evidence = evidence
        self.diagnostics = diagnostics
    }
}

public struct GitHistoryEvidenceProvider: Sendable {
    private static let maximumCommitsPerFile = 500

    private let executableURL: URL
    private let baseArguments: [String]
    private let timeoutSeconds: TimeInterval
    private let runner: any GitHistoryProcessRunning

    public init(timeoutSeconds: TimeInterval = 5) {
        self.init(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            baseArguments: ["git"],
            timeoutSeconds: timeoutSeconds,
            runner: GitHistorySubprocessRunner()
        )
    }

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        baseArguments: [String] = ["git"],
        timeoutSeconds: TimeInterval = 5,
        runner: any GitHistoryProcessRunning
    ) {
        self.executableURL = executableURL
        self.baseArguments = baseArguments
        self.timeoutSeconds = timeoutSeconds
        self.runner = runner
    }

    public func evidence(for request: GitHistoryEvidenceRequest) -> GitHistoryEvidenceResult {
        let root = URL(fileURLWithPath: request.repositoryRoot)
        let entities = request.entities.sorted(by: entityOrder)
        guard !entities.isEmpty else { return GitHistoryEvidenceResult(evidence: []) }

        if let unavailable = repositoryUnavailableReason(root: root) {
            return unavailableResult(for: entities, reason: unavailable)
        }

        let paths = Set(entities.compactMap(\.location.file)).sorted()
        guard !paths.isEmpty else {
            return unavailableResult(for: entities, reason: "no entity file locations")
        }

        var historyByPath: [String: FileHistory] = [:]
        var unavailableReasonByPath: [String: String] = [:]
        var diagnostics: [GitHistoryEvidenceDiagnostic] = []
        for path in paths {
            let log = runGit(
                [
                    "log", "--follow", "--max-count=\(Self.maximumCommitsPerFile + 1)",
                    "--format=%x1e%H%x1f%aE%x1f%aI%x1f%s", "--name-only", "--", path,
                ],
                root: root
            )
            guard !log.timedOut, log.exitCode == 0 else {
                let reason = "git log failed for \(path): \(diagnosticText(log))"
                unavailableReasonByPath[path] = reason
                diagnostics.append(.init(message: reason))
                continue
            }
            let commits = parseCommits(log.stdout).sorted(by: commitOrder)
            historyByPath[path] = FileHistory(
                commits: Array(commits.prefix(Self.maximumCommitsPerFile)),
                isTruncated: commits.count > Self.maximumCommitsPerFile
            )
        }

        var evidence: [DebtEvidence] = []
        for entity in entities {
            guard let file = entity.location.file else {
                evidence += unavailableEvidence(for: entity, reason: "entity has no file location")
                continue
            }
            if let reason = unavailableReasonByPath[file] {
                evidence += unavailableEvidence(for: entity, reason: reason)
                continue
            }
            guard let history = historyByPath[file], !history.commits.isEmpty else {
                evidence += unavailableEvidence(for: entity, reason: "no git commits matched entity file")
                continue
            }
            evidence += availableEvidence(
                for: entity,
                commits: history.commits,
                referenceTime: request.referenceTime,
                isTruncated: history.isTruncated
            )
        }
        return GitHistoryEvidenceResult(evidence: evidence.sorted(by: evidenceOrder), diagnostics: diagnostics)
    }

    private func repositoryUnavailableReason(root: URL) -> String? {
        let inside = runGit(["rev-parse", "--is-inside-work-tree"], root: root)
        guard inside.exitCode == 0, inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return "not a git repository: \(diagnosticText(inside))"
        }
        let shallow = runGit(["rev-parse", "--is-shallow-repository"], root: root)
        guard shallow.exitCode == 0 else {
            return "unable to inspect git history depth: \(diagnosticText(shallow))"
        }
        if shallow.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" {
            return "shallow git history is unavailable"
        }
        let count = runGit(["rev-list", "--count", "HEAD"], root: root)
        guard count.exitCode == 0, let value = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
            return "git repository has no commits: \(diagnosticText(count))"
        }
        return nil
    }

    private func availableEvidence(
        for entity: DebtEntity,
        commits: [GitCommitRecord],
        referenceTime: Date,
        isTruncated: Bool
    ) -> [DebtEvidence] {
        let total = commits.count
        let latest = commits.map(\.timestamp).max() ?? referenceTime
        let days = max(0, Int(referenceTime.timeIntervalSince(latest) / 86_400))
        let fixCount = commits.filter { isFixOriented($0.subject) }.count
        let contributors = Dictionary(grouping: commits, by: \.authorToken)
        let topShare = Double(contributors.values.map(\.count).max() ?? 0) / Double(total)
        return historyEvidence(
            for: entity,
            total: total,
            latest: latest,
            days: days,
            fixCount: fixCount,
            contributorCount: contributors.count,
            topShare: topShare,
            referenceTime: referenceTime,
            historyLimit: Self.maximumCommitsPerFile,
            isTruncated: isTruncated
        )
    }

    private func unavailableResult(for entities: [DebtEntity], reason: String) -> GitHistoryEvidenceResult {
        GitHistoryEvidenceResult(
            evidence: entities.flatMap { unavailableEvidence(for: $0, reason: reason) }.sorted(by: evidenceOrder),
            diagnostics: [.init(message: reason)]
        )
    }

    private func runGit(_ arguments: [String], root: URL) -> GitHistoryProcessResult {
        runner.run(
            executableURL: executableURL,
            arguments: baseArguments + ["-C", root.path] + arguments,
            workingDirectory: root,
            timeoutSeconds: timeoutSeconds
        )
    }
}

private struct FileHistory: Sendable {
    let commits: [GitCommitRecord]
    let isTruncated: Bool
}
