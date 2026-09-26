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

public struct IntroductionConclusion: Equatable, Sendable {
    public let findingID: FindingID
    public let attempt: UInt
    public let kind: IntroductionConclusionKind
    public let exactRevision: GitRevisionID?
    public let earliestPositiveRevision: GitRevisionID?
    public let reasons: [LifecycleReason]
    public let evidence: IntroductionHistoryEvidence
    public let semanticComparisons: [SemanticComparisonBasis]
    public let evidenceContract: LifecycleEvidenceContract

    package init(
        findingID: FindingID,
        attempt: UInt,
        kind: IntroductionConclusionKind,
        exactRevision: GitRevisionID?,
        earliestPositiveRevision: GitRevisionID?,
        reasons: [LifecycleReason],
        evidence: IntroductionHistoryEvidence,
        semanticComparisons: [SemanticComparisonBasis],
        evidenceContract: LifecycleEvidenceContract = .semanticComparisonV1
    ) {
        self.findingID = findingID
        self.attempt = attempt
        self.kind = kind
        self.exactRevision = exactRevision
        self.earliestPositiveRevision = earliestPositiveRevision
        self.reasons = reasons.sorted(by: lifecycleReasonOrder)
        self.evidence = evidence
        self.semanticComparisons = uniqueSemanticComparisons(semanticComparisons)
        self.evidenceContract = evidenceContract
    }
}

extension IntroductionConclusion: Codable {
    private enum CodingKeys: String, CodingKey {
        case findingID
        case attempt
        case kind
        case exactRevision
        case earliestPositiveRevision
        case reasons
        case evidence
        case semanticComparisons
        case evidenceContract
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let comparisons =
            try values.decodeIfPresent(
                [SemanticComparisonBasis].self,
                forKey: .semanticComparisons
            ) ?? []
        guard comparisons == uniqueSemanticComparisons(comparisons) else {
            throw DecodingError.dataCorruptedError(
                forKey: .semanticComparisons,
                in: values,
                debugDescription: "Semantic comparison evidence must be unique and canonical."
            )
        }
        self.init(
            findingID: try values.decode(FindingID.self, forKey: .findingID),
            attempt: try values.decode(UInt.self, forKey: .attempt),
            kind: try values.decode(IntroductionConclusionKind.self, forKey: .kind),
            exactRevision: try values.decodeIfPresent(GitRevisionID.self, forKey: .exactRevision),
            earliestPositiveRevision: try values.decodeIfPresent(
                GitRevisionID.self,
                forKey: .earliestPositiveRevision
            ),
            reasons: try values.decode([LifecycleReason].self, forKey: .reasons),
            evidence: try values.decode(IntroductionHistoryEvidence.self, forKey: .evidence),
            semanticComparisons: comparisons,
            evidenceContract: try values.decode(LifecycleEvidenceContract.self, forKey: .evidenceContract)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(findingID, forKey: .findingID)
        try values.encode(attempt, forKey: .attempt)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(exactRevision, forKey: .exactRevision)
        try values.encodeIfPresent(earliestPositiveRevision, forKey: .earliestPositiveRevision)
        try values.encode(reasons, forKey: .reasons)
        try values.encode(evidence, forKey: .evidence)
        try values.encode(evidenceContract, forKey: .evidenceContract)
        if !semanticComparisons.isEmpty {
            try values.encode(semanticComparisons, forKey: .semanticComparisons)
        }
    }
}
