import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax

extension LifecycleIntroductionService {
    func captureHistory(
        startingRevision: GitRevisionID?,
        repositoryURL: URL,
        maximumRevisions: Int,
        maximumFileBytes: Int
    ) throws -> (revisions: [IntroductionHistoryRevision], frontier: [GitRevisionID]) {
        guard let startingRevision else { return ([], []) }
        var queue = [startingRevision]
        var scheduled: Set<GitRevisionID> = [startingRevision]
        var revisions: [IntroductionHistoryRevision] = []

        while revisions.count < maximumRevisions, !queue.isEmpty {
            let revision = queue.removeFirst()
            let parentsResult = runGit(
                ["show", "-s", "--format=%P", revision.rawValue],
                repositoryURL: repositoryURL
            )
            guard parentsResult.exitCode == 0, !parentsResult.timedOut else {
                revisions.append(
                    IntroductionHistoryRevision(
                        revision: revision,
                        parentRevisions: [],
                        unavailableReason: try reason(
                            code: "history-revision-unavailable",
                            message: diagnosticText(parentsResult)
                        )
                    )
                )
                continue
            }
            let parents: [GitRevisionID]
            do {
                parents = try parentsResult.stdout.split(whereSeparator: { $0.isWhitespace }).map {
                    try GitRevisionID(String($0))
                }.sorted { $0.rawValue < $1.rawValue }
            } catch {
                revisions.append(
                    IntroductionHistoryRevision(
                        revision: revision,
                        parentRevisions: [],
                        unavailableReason: try reason(
                            code: "history-parent-invalid",
                            message: String(describing: error)
                        )
                    )
                )
                continue
            }
            do {
                let observation = try observe(
                    revision: revision,
                    parents: parents,
                    repositoryURL: repositoryURL,
                    maximumFileBytes: maximumFileBytes
                )
                revisions.append(
                    IntroductionHistoryRevision(
                        revision: revision,
                        parentRevisions: parents,
                        observation: observation
                    )
                )
            } catch {
                revisions.append(
                    IntroductionHistoryRevision(
                        revision: revision,
                        parentRevisions: parents,
                        unavailableReason: try reason(
                            code: "historical-source-unavailable",
                            message: String(describing: error)
                        )
                    )
                )
            }
            for parent in parents where scheduled.insert(parent).inserted {
                queue.append(parent)
            }
        }
        return (revisions, queue.sorted { $0.rawValue < $1.rawValue })
    }

    func ancestryReasons(
        startingRevision: GitRevisionID?,
        headRevision: GitRevisionID,
        repositoryURL: URL
    ) throws -> [LifecycleReason] {
        guard let startingRevision, startingRevision != headRevision else { return [] }
        let result = runGit(
            ["merge-base", "--is-ancestor", startingRevision.rawValue, headRevision.rawValue],
            repositoryURL: repositoryURL
        )
        switch (result.exitCode, result.timedOut) {
        case (0, false):
            return []
        case (1, false):
            return [
                try reason(
                    code: "starting-revision-not-ancestor",
                    message: "The First Observation revision is not an ancestor of the captured repository HEAD."
                )
            ]
        default:
            return [
                try reason(
                    code: "history-ancestry-unavailable",
                    message: diagnosticText(result)
                )
            ]
        }
    }

}
