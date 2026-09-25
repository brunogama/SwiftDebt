public enum IntroductionConclusionKind: String, Codable, Equatable, Sendable {
    case exact
    case bounded
    case unavailable
}

public struct IntroductionHistoryBoundary: Codable, Equatable, Sendable {
    public let startingRevision: GitRevisionID?
    public let repositoryHeadRevision: GitRevisionID
    public let workingTreeState: SourceWorkingTreeState
    public let workingTreeStatusDigest: LifecycleDigest
    public let isShallow: Bool
    public let maximumRevisions: Int
    public let frontierRevisions: [GitRevisionID]
    public let limitingReasons: [LifecycleReason]

    package init(
        startingRevision: GitRevisionID?,
        repositoryHeadRevision: GitRevisionID,
        workingTreeState: SourceWorkingTreeState,
        workingTreeStatusDigest: LifecycleDigest,
        isShallow: Bool,
        maximumRevisions: Int,
        frontierRevisions: [GitRevisionID],
        limitingReasons: [LifecycleReason] = []
    ) {
        self.startingRevision = startingRevision
        self.repositoryHeadRevision = repositoryHeadRevision
        self.workingTreeState = workingTreeState
        self.workingTreeStatusDigest = workingTreeStatusDigest
        self.isShallow = isShallow
        self.maximumRevisions = maximumRevisions
        self.frontierRevisions = frontierRevisions.sorted { $0.rawValue < $1.rawValue }
        self.limitingReasons = limitingReasons.sorted(by: lifecycleReasonOrder)
    }
}

public struct IntroductionHistoryRevision: Codable, Equatable, Sendable {
    public let revision: GitRevisionID
    public let parentRevisions: [GitRevisionID]
    public let observation: ObservationSnapshot?
    public let unavailableReason: LifecycleReason?

    package init(
        revision: GitRevisionID,
        parentRevisions: [GitRevisionID],
        observation: ObservationSnapshot
    ) {
        self.revision = revision
        self.parentRevisions = parentRevisions.sorted { $0.rawValue < $1.rawValue }
        self.observation = observation
        self.unavailableReason = nil
    }

    package init(
        revision: GitRevisionID,
        parentRevisions: [GitRevisionID],
        unavailableReason: LifecycleReason
    ) {
        self.revision = revision
        self.parentRevisions = parentRevisions.sorted { $0.rawValue < $1.rawValue }
        self.observation = nil
        self.unavailableReason = unavailableReason
    }
}

public struct IntroductionHistoryEvidence: Codable, Equatable, Sendable {
    public let boundary: IntroductionHistoryBoundary
    public let revisions: [IntroductionHistoryRevision]

    package init(
        boundary: IntroductionHistoryBoundary,
        revisions: [IntroductionHistoryRevision]
    ) {
        self.boundary = boundary
        self.revisions = revisions
    }
}

public struct IntroductionConclusion: Codable, Equatable, Sendable {
    public let findingID: FindingID
    public let attempt: UInt
    public let kind: IntroductionConclusionKind
    public let exactRevision: GitRevisionID?
    public let earliestPositiveRevision: GitRevisionID?
    public let reasons: [LifecycleReason]
    public let evidence: IntroductionHistoryEvidence

    package init(
        findingID: FindingID,
        attempt: UInt,
        kind: IntroductionConclusionKind,
        exactRevision: GitRevisionID?,
        earliestPositiveRevision: GitRevisionID?,
        reasons: [LifecycleReason],
        evidence: IntroductionHistoryEvidence
    ) {
        self.findingID = findingID
        self.attempt = attempt
        self.kind = kind
        self.exactRevision = exactRevision
        self.earliestPositiveRevision = earliestPositiveRevision
        self.reasons = reasons.sorted(by: lifecycleReasonOrder)
        self.evidence = evidence
    }
}
