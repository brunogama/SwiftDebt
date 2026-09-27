import SwiftDebtCore
import SwiftDebtLifecycle

struct LifecycleIntroductionReuseQuery: Sendable {
    let startingRevision: GitRevisionID?
    let repositoryHeadRevision: GitRevisionID
    let workingTreeState: SourceWorkingTreeState
    let workingTreeStatusDigest: LifecycleDigest
    let isShallow: Bool
    let maximumRevisions: Int
    let limitingReasons: [LifecycleReason]

    func matches(_ boundary: IntroductionHistoryBoundary) -> Bool {
        boundary.startingRevision == startingRevision
            && boundary.repositoryHeadRevision == repositoryHeadRevision
            && boundary.workingTreeState == workingTreeState
            && boundary.workingTreeStatusDigest == workingTreeStatusDigest
            && boundary.isShallow == isShallow
            && boundary.maximumRevisions == maximumRevisions
            && boundary.limitingReasons == limitingReasons
    }
}

struct LifecycleIntroductionHistoryReuse: Sendable {
    private struct RevisionKey: Hashable, Sendable {
        let revision: GitRevisionID
        let parents: [GitRevisionID]
    }

    private let observations: [RevisionKey: [ObservationSnapshot]]

    init(
        artifact: LifecycleArtifact,
        findingID: FindingID,
        query: LifecycleIntroductionReuseQuery
    ) {
        guard query.workingTreeState == .clean, !query.isShallow else {
            observations = [:]
            return
        }
        var collected: [RevisionKey: [ObservationSnapshot]] = [:]
        for conclusion in artifact.introductionConclusions(for: findingID)
        where conclusion.evidenceContract == .semanticComparisonV1
            && query.matches(conclusion.evidence.boundary)
        {
            for record in conclusion.evidence.revisions {
                guard let observation = record.observation else { continue }
                let key = RevisionKey(
                    revision: record.revision,
                    parents: record.parentRevisions
                )
                collected[key, default: []].append(observation)
            }
        }
        observations = collected
    }

    func candidates(
        for revision: GitRevisionID,
        parents: [GitRevisionID]
    ) -> [ObservationSnapshot] {
        observations[RevisionKey(revision: revision, parents: parents)] ?? []
    }
}

struct LifecycleIntroductionObservationIdentity: Sendable {
    let snapshotID: SnapshotID
    let provenance: SnapshotProvenance
    let rules: [SnapshotRule]
    let sourcePaths: [SourcePath]
    let defaultSeverities: [RuleIdentity: RuleSeverity]

    func matchingObservation(
        among candidates: [ObservationSnapshot]
    ) -> ObservationSnapshot? {
        let compatible = candidates.filter {
            $0.isAtomicallyComplete
                && $0.id == snapshotID
                && $0.provenance == provenance
                && $0.rules == rules
                && $0.sources.map(\.sourcePath) == sourcePaths
                && $0.detections.allSatisfy {
                    defaultSeverities[$0.rule.identity] == $0.severity
                }
        }
        guard let first = compatible.first,
            compatible.dropFirst().allSatisfy({ $0 == first })
        else {
            return nil
        }
        return first
    }
}
