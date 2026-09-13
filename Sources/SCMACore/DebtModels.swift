public enum DebtAggregationLevel: String, Codable, CaseIterable, Sendable {
    case callable
    case type
    case file
    case module
}

public struct DebtLocation: Codable, Hashable, Sendable {
    public let module: String?
    public let file: String?
    public let line: Int?
    public let column: Int?

    public init(module: String? = nil, file: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.module = module
        self.file = file
        self.line = line
        self.column = column
    }

    public init(module: String? = nil, source: SourceLocation) {
        self.init(module: module, file: source.file, line: source.line, column: source.column)
    }
}

public struct DebtEntity: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let level: DebtAggregationLevel
    public let location: DebtLocation

    public init(id: String, displayName: String, level: DebtAggregationLevel, location: DebtLocation) {
        self.id = id
        self.displayName = displayName
        self.level = level
        self.location = location
    }
}

public struct DebtItem: Codable, Equatable, Sendable {
    public let id: String
    public let entity: DebtEntity
    public let evidence: [DebtEvidence]

    public init(id: String, entity: DebtEntity, evidence: [DebtEvidence]) {
        self.id = id
        self.entity = entity
        self.evidence = evidence
    }
}

public struct DebtEvidenceAvailability: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case available
        case unavailable
        case missingFile
        case unmatchedEntity
        case zeroCoverage
        case measuredCoverage
    }

    public let state: State
    public let reason: String?

    public init(state: State, reason: String? = nil) {
        self.state = state
        self.reason = reason
    }

    public static var available: DebtEvidenceAvailability {
        DebtEvidenceAvailability(state: .available)
    }

    public static func unavailable(reason: String? = nil) -> DebtEvidenceAvailability {
        DebtEvidenceAvailability(state: .unavailable, reason: reason)
    }

    public var isAvailable: Bool {
        state == .available || state == .zeroCoverage || state == .measuredCoverage
    }
}

public enum DebtEvidenceRequirement: String, Codable, Sendable {
    case required
    case optional
}

public struct DebtEvidence: Codable, Equatable, Sendable {
    public let id: String
    public let kind: String
    public let requirement: DebtEvidenceRequirement
    public let availability: DebtEvidenceAvailability
    public let weight: Double
    public let normalizedScore: Double?
    public let rawValue: String
    public let location: DebtLocation?
    public let note: String?

    public init(
        id: String,
        kind: String,
        requirement: DebtEvidenceRequirement = .optional,
        availability: DebtEvidenceAvailability = .available,
        weight: Double,
        normalizedScore: Double?,
        rawValue: String,
        location: DebtLocation? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.requirement = requirement
        self.availability = availability
        self.weight = weight
        self.normalizedScore = normalizedScore
        self.rawValue = rawValue
        self.location = location
        self.note = note
    }
}

public struct DebtAggregation: Codable, Equatable, Sendable {
    public let id: String
    public let level: DebtAggregationLevel
    public let displayName: String
    public let location: DebtLocation
    public let memberItemIDs: [String]
    public let score: DebtScore?

    public init(
        id: String,
        level: DebtAggregationLevel,
        displayName: String,
        location: DebtLocation,
        memberItemIDs: [String],
        score: DebtScore? = nil
    ) {
        self.id = id
        self.level = level
        self.displayName = displayName
        self.location = location
        self.memberItemIDs = memberItemIDs
        self.score = score
    }
}
