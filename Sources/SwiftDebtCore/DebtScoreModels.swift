public enum Priority: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
    case critical
}

public struct PriorityThresholds: Codable, Equatable, Sendable {
    public let medium: Double
    public let high: Double
    public let critical: Double

    public init(medium: Double = 40, high: Double = 70, critical: Double = 85) {
        self.medium = medium
        self.high = high
        self.critical = critical
    }

    public func classify(_ score: Double) -> Priority {
        if score >= critical { return .critical }
        if score >= high { return .high }
        if score >= medium { return .medium }
        return .low
    }
}

public struct DebtScoringPolicy: Codable, Equatable, Sendable {
    public let priorityThresholds: PriorityThresholds

    public init(priorityThresholds: PriorityThresholds = PriorityThresholds()) {
        self.priorityThresholds = priorityThresholds
    }
}

public struct DebtScoreContribution: Codable, Equatable, Sendable {
    public let evidenceID: String
    public let kind: String
    public let rawValue: String
    public let normalizedScore: Double
    public let configuredWeight: Double
    public let effectiveWeight: Double
    public let contribution: Double
    public let note: String?

    public init(
        evidenceID: String,
        kind: String,
        rawValue: String,
        normalizedScore: Double,
        configuredWeight: Double,
        effectiveWeight: Double,
        contribution: Double,
        note: String? = nil
    ) {
        self.evidenceID = evidenceID
        self.kind = kind
        self.rawValue = rawValue
        self.normalizedScore = normalizedScore
        self.configuredWeight = configuredWeight
        self.effectiveWeight = effectiveWeight
        self.contribution = contribution
        self.note = note
    }
}

public struct DebtUnavailableEvidence: Codable, Equatable, Sendable {
    public let evidenceID: String
    public let kind: String
    public let requirement: DebtEvidenceRequirement
    public let configuredWeight: Double
    public let reason: String?

    public init(
        evidenceID: String,
        kind: String,
        requirement: DebtEvidenceRequirement,
        configuredWeight: Double,
        reason: String? = nil
    ) {
        self.evidenceID = evidenceID
        self.kind = kind
        self.requirement = requirement
        self.configuredWeight = configuredWeight
        self.reason = reason
    }
}

public struct DebtScoreBreakdown: Codable, Equatable, Sendable {
    public let totalConfiguredWeight: Double
    public let totalAvailableWeight: Double
    public let contributions: [DebtScoreContribution]
    public let unavailableEvidence: [DebtUnavailableEvidence]

    public init(
        totalConfiguredWeight: Double,
        totalAvailableWeight: Double,
        contributions: [DebtScoreContribution],
        unavailableEvidence: [DebtUnavailableEvidence]
    ) {
        self.totalConfiguredWeight = totalConfiguredWeight
        self.totalAvailableWeight = totalAvailableWeight
        self.contributions = contributions
        self.unavailableEvidence = unavailableEvidence
    }
}

public struct DebtScore: Codable, Equatable, Sendable {
    public let value: Double?
    public let priority: Priority?
    public let breakdown: DebtScoreBreakdown

    public init(value: Double?, priority: Priority?, breakdown: DebtScoreBreakdown) {
        self.value = value
        self.priority = priority
        self.breakdown = breakdown
    }
}
