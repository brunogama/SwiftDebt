public struct SourceLocation: Codable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int = 1) {
        self.file = file
        self.line = line
        self.column = column
    }
}

public struct SourceUnit: Sendable {
    public let path: String
    public let module: String
    public let content: String

    public init(path: String, module: String = "Workspace", content: String) {
        self.path = path
        self.module = module
        self.content = content
    }
}

public struct AnalysisDiagnostic: Codable, Sendable, Equatable {
    public enum Severity: String, Codable, Sendable { case warning, error }
    public let severity: Severity
    public let message: String
    public let location: SourceLocation

    public init(severity: Severity, message: String, location: SourceLocation) {
        self.severity = severity
        self.message = message
        self.location = location
    }
}

public struct MetricObservation: Codable, Sendable, Equatable {
    public let entity: String
    public let location: SourceLocation
    public let value: Int

    public init(entity: String, location: SourceLocation, value: Int) {
        self.entity = entity
        self.location = location
        self.value = value
    }
}

public struct MetricSummary: Codable, Sendable {
    public let metric: Metric
    public let observations: [MetricObservation]
    public let threshold: Int?
    public let violations: Int
    public let paperViolations: Int?
    public let maximum: Int?
    public let total: Int
    public let score: Double?
    public let scoreNote: String?
    public let measurementNote: String?

    private enum CodingKeys: String, CodingKey {
        case metric
        case observations
        case threshold
        case violations
        case paperViolations
        case maximum
        case total
        case score
        case scoreNote
        case measurementNote
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(metric, forKey: .metric)
        try values.encode(observations, forKey: .observations)
        try values.encode(threshold, forKey: .threshold)
        try values.encode(violations, forKey: .violations)
        try values.encode(paperViolations, forKey: .paperViolations)
        try values.encode(maximum, forKey: .maximum)
        try values.encode(total, forKey: .total)
        try values.encode(score, forKey: .score)
        try values.encode(scoreNote, forKey: .scoreNote)
        try values.encode(measurementNote, forKey: .measurementNote)
    }
}

public struct Finding: Codable, Sendable {
    public let metric: Metric
    public let entity: String
    public let location: SourceLocation
    public let value: Int
    public let threshold: Int
}

public struct CouplingEdge: Codable, Hashable, Sendable {
    public let first: String
    public let second: String
}

public struct DuplicateOccurrence: Codable, Hashable, Sendable {
    public let file: String
    public let startLine: Int
    public let endLine: Int
    public let codeLines: Int
}

public struct DuplicateBlock: Codable, Hashable, Sendable {
    public let first: DuplicateOccurrence
    public let second: DuplicateOccurrence
}
