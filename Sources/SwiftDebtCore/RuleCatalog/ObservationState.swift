/// Why a rule's observation fell short of `.complete` because it could not
/// observe (as opposed to `.failed`, where observation attempted and erred).
public enum PartialReason: Codable, Hashable, Sendable {
    case requiredEvidenceUnavailable(EvidenceRequirement)
    case scopeNotEvaluated(RuleScope)
    case other(String)
}

public enum UnavailableReason: Codable, Hashable, Sendable {
    case capabilityNotProvided(AnalysisCapability)
    case externalProviderMissing
    case runtimeNotObserved
    case other(String)
}

public struct RuleAnalysisFailure: Codable, Hashable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

/// Distinguishes "no Detection" from "could not observe" (PRD FR-10,
/// Invariant Q3/Q9). `.complete` with zero Detections is verified absence;
/// every other case must never be reported or reconciled as absence
/// (Invariant Q3, SM-2).
public enum ObservationState: Codable, Hashable, Sendable {
    case complete
    case partial(reason: PartialReason)
    case unavailable(reason: UnavailableReason)
    case failed(RuleAnalysisFailure)
    case disabled

    /// True only when a zero-Detection result for this state is a valid
    /// claim of verified absence.
    public var provesAbsenceWhenNoDetection: Bool {
        self == .complete
    }
}
