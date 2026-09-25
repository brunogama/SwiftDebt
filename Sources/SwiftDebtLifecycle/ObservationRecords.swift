import SwiftDebtCore

public struct ObservedDetection: Equatable, Sendable {
    public let id: DetectionID
    public let rule: SnapshotRule
    public let severity: RuleSeverity
    public let location: SnapshotLocation
    public let message: String

    public init(
        id: DetectionID,
        rule: SnapshotRule,
        severity: RuleSeverity,
        location: SnapshotLocation,
        message: String
    ) throws {
        guard hasLifecycleContent(message) else {
            throw LifecycleContractError.invalidSnapshot("Detection messages must be nonblank single lines.")
        }
        self.id = id
        self.rule = rule
        self.severity = severity
        self.location = location
        self.message = message
    }
}

extension ObservedDetection: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case rule
        case severity
        case location
        case message
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let severityValue = try values.decode(String.self, forKey: .severity)
        guard let severity = RuleSeverity(rawValue: severityValue) else {
            throw DecodingError.dataCorruptedError(
                forKey: .severity,
                in: values,
                debugDescription: "Unknown rule severity \(severityValue)."
            )
        }
        do {
            try self.init(
                id: values.decode(DetectionID.self, forKey: .id),
                rule: values.decode(SnapshotRule.self, forKey: .rule),
                severity: severity,
                location: values.decode(SnapshotLocation.self, forKey: .location),
                message: values.decode(String.self, forKey: .message)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(rule, forKey: .rule)
        try values.encode(severity.rawValue, forKey: .severity)
        try values.encode(location, forKey: .location)
        try values.encode(message, forKey: .message)
    }
}

public struct AtomicObservation: Equatable, Sendable {
    public let id: AtomicObservationID
    public let rule: SnapshotRule
    public let sourcePath: SourcePath
    public let outcome: AtomicObservationOutcome

    public init(
        id: AtomicObservationID,
        rule: SnapshotRule,
        sourcePath: SourcePath,
        outcome: AtomicObservationOutcome
    ) {
        self.id = id
        self.rule = rule
        self.sourcePath = sourcePath
        self.outcome = outcome
    }
}

extension AtomicObservation: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case rule
        case sourcePath
        case outcome
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            self.init(
                id: try values.decode(AtomicObservationID.self, forKey: .id),
                rule: try values.decode(SnapshotRule.self, forKey: .rule),
                sourcePath: try SourcePath(values.decode(String.self, forKey: .sourcePath)),
                outcome: try values.decode(AtomicObservationOutcome.self, forKey: .outcome)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .sourcePath,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(rule, forKey: .rule)
        try values.encode(sourcePath.rawValue, forKey: .sourcePath)
        try values.encode(outcome, forKey: .outcome)
    }
}
