import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax

extension LifecycleIntroductionService {
    struct HistoryCapture: Sendable {
        let revisions: [IntroductionHistoryRevision]
        let frontier: [GitRevisionID]
        let analyzedRevisionCount: Int
        let reusedRevisionCount: Int
    }

    func captureHistory(
        startingRevision: GitRevisionID?,
        repositoryURL: URL,
        maximumRevisions: Int,
        maximumFileBytes: Int,
        reuse: LifecycleIntroductionHistoryReuse
    ) throws -> HistoryCapture {
        guard let startingRevision else {
            return HistoryCapture(
                revisions: [],
                frontier: [],
                analyzedRevisionCount: 0,
                reusedRevisionCount: 0
            )
        }
        var queue = [startingRevision]
        var scheduled: Set<GitRevisionID> = [startingRevision]
        var revisions: [IntroductionHistoryRevision] = []
        var analyzedRevisionCount = 0
        var reusedRevisionCount = 0

        while revisions.count < maximumRevisions, !queue.isEmpty {
            let revision = queue.removeFirst()
            let parentsResult = runGit(
                ["show", "-s", "--format=%P", revision.rawValue],
                repositoryURL: repositoryURL
            )
            guard parentsResult.exitCode == 0, !parentsResult.timedOut else {
                analyzedRevisionCount += 1
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
                analyzedRevisionCount += 1
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
                let result = try observe(
                    revision: revision,
                    parents: parents,
                    repositoryURL: repositoryURL,
                    maximumFileBytes: maximumFileBytes,
                    reuseCandidates: reuse.candidates(for: revision, parents: parents)
                )
                if result.reused {
                    reusedRevisionCount += 1
                } else {
                    analyzedRevisionCount += 1
                }
                revisions.append(
                    IntroductionHistoryRevision(
                        revision: revision,
                        parentRevisions: parents,
                        observation: result.observation
                    )
                )
            } catch {
                analyzedRevisionCount += 1
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
        return HistoryCapture(
            revisions: revisions,
            frontier: queue.sorted { $0.rawValue < $1.rawValue },
            analyzedRevisionCount: analyzedRevisionCount,
            reusedRevisionCount: reusedRevisionCount
        )
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
