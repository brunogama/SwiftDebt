import SwiftDebtCore

public enum FindingLifecycleState: String, Codable, Equatable, Sendable {
    case open
    case resolved
}

public enum FindingEvidenceState: String, Codable, Equatable, Sendable {
    case observed
    case unverified
    case continuityAmbiguous = "continuity-ambiguous"
    case verifiedAbsent = "verified-absent"
}

public struct DetectionEvidence: Codable, Equatable, Sendable {
    public let detectionID: DetectionID
    public let atomicObservationID: AtomicObservationID

    public init(detectionID: DetectionID, atomicObservationID: AtomicObservationID) {
        self.detectionID = detectionID
        self.atomicObservationID = atomicObservationID
    }
}

public struct ResolutionEvidence: Codable, Equatable, Sendable {
    public let priorSnapshotID: SnapshotID
    public let coveredAtomicObservationIDs: [AtomicObservationID]
    public let reasons: [LifecycleReason]

    public init(
        priorSnapshotID: SnapshotID,
        coveredAtomicObservationIDs: [AtomicObservationID],
        reasons: [LifecycleReason]
    ) {
        self.priorSnapshotID = priorSnapshotID
        self.coveredAtomicObservationIDs = coveredAtomicObservationIDs.sorted { $0.rawValue < $1.rawValue }
        self.reasons = reasons.sorted(by: lifecycleReasonOrder)
    }
}

public struct ContinuityAmbiguityEvidence: Codable, Equatable, Sendable {
    public let currentDetectionIDs: [DetectionID]
    public let candidateFindingIDs: [FindingID]
    public let reasons: [LifecycleReason]

    public init(
        currentDetectionIDs: [DetectionID],
        candidateFindingIDs: [FindingID],
        reasons: [LifecycleReason]
    ) {
        self.currentDetectionIDs = currentDetectionIDs.sorted { $0.rawValue < $1.rawValue }
        self.candidateFindingIDs = candidateFindingIDs.sorted { $0.rawValue < $1.rawValue }
        self.reasons = reasons.sorted(by: lifecycleReasonOrder)
    }
}

public enum LifecycleTransition: Equatable, Sendable {
    case opened(DetectionEvidence)
    case resolved(ResolutionEvidence)
    case unverified([LifecycleReason])
    case continuityAmbiguous(ContinuityAmbiguityEvidence)

    public enum Kind: String, Codable, Sendable {
        case opened
        case resolved
        case unverified
        case continuityAmbiguous = "continuity-ambiguous"
    }

    public var kind: Kind {
        switch self {
        case .opened: .opened
        case .resolved: .resolved
        case .unverified: .unverified
        case .continuityAmbiguous: .continuityAmbiguous
        }
    }
}

extension LifecycleTransition: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case detection
        case resolution
        case reasons
        case ambiguity
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .opened:
            self = .opened(try values.decode(DetectionEvidence.self, forKey: .detection))
        case .resolved:
            self = .resolved(try values.decode(ResolutionEvidence.self, forKey: .resolution))
        case .unverified:
            let reasons = try values.decode([LifecycleReason].self, forKey: .reasons)
            guard !reasons.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .reasons,
                    in: values,
                    debugDescription: "An unverified event requires at least one blocker."
                )
            }
            self = .unverified(reasons.sorted(by: lifecycleReasonOrder))
        case .continuityAmbiguous:
            self = .continuityAmbiguous(
                try values.decode(ContinuityAmbiguityEvidence.self, forKey: .ambiguity)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        switch self {
        case .opened(let evidence):
            try values.encode(evidence, forKey: .detection)
        case .resolved(let evidence):
            try values.encode(evidence, forKey: .resolution)
        case .unverified(let reasons):
            try values.encode(reasons.sorted(by: lifecycleReasonOrder), forKey: .reasons)
        case .continuityAmbiguous(let evidence):
            try values.encode(evidence, forKey: .ambiguity)
        }
    }
}

public struct LifecycleEvent: Codable, Equatable, Sendable {
    public let id: LifecycleEventID
    public let snapshotID: SnapshotID
    public let transition: LifecycleTransition

    public init(id: LifecycleEventID, snapshotID: SnapshotID, transition: LifecycleTransition) {
        self.id = id
        self.snapshotID = snapshotID
        self.transition = transition
    }
}
