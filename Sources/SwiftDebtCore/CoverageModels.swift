public struct LcovFunctionDefinition: Codable, Equatable, Sendable {
    public let line: Int
    public let name: String

    public init(line: Int, name: String) {
        self.line = line
        self.name = name
    }
}

public struct LcovFunctionHit: Codable, Equatable, Sendable {
    public let name: String
    public let hits: Int

    public init(name: String, hits: Int) {
        self.name = name
        self.hits = hits
    }
}

public struct LcovLineHit: Codable, Equatable, Sendable {
    public let line: Int
    public let hits: Int

    public init(line: Int, hits: Int) {
        self.line = line
        self.hits = hits
    }
}

public struct LcovRecord: Codable, Equatable, Sendable {
    public let sourcePath: String
    public let functions: [LcovFunctionDefinition]
    public let functionHits: [LcovFunctionHit]
    public let lineHits: [LcovLineHit]

    public init(
        sourcePath: String,
        functions: [LcovFunctionDefinition] = [],
        functionHits: [LcovFunctionHit] = [],
        lineHits: [LcovLineHit] = []
    ) {
        self.sourcePath = sourcePath
        self.functions = functions
        self.functionHits = functionHits
        self.lineHits = lineHits
    }
}

public struct LcovReport: Codable, Equatable, Sendable {
    public let records: [LcovRecord]

    public init(records: [LcovRecord]) {
        self.records = records
    }
}

public enum CoverageMatchingStrategy: String, Codable, CaseIterable, Sendable {
    case sourcePathExact
    case sourcePathSuffix
    case functionNameExact
    case functionNameSuffix
    case functionStartLine
    case executableLine
}

public enum CoverageMatchingConfidence: String, Codable, Sendable {
    case exact
    case high
    case fallback
    case unmatched
}

public enum CoverageAvailability: String, Codable, Sendable {
    case missingFile
    case unmatchedEntity
    case zeroCoverage
    case measuredCoverage
}

public struct CoverageDiagnostic: Codable, Equatable, Sendable {
    public let entityID: String?
    public let entityDisplayName: String?
    public let sourcePath: String?
    public let matchedSourcePath: String?
    public let matchedFunction: String?
    public let availability: CoverageAvailability
    public let confidence: CoverageMatchingConfidence
    public let attemptedStrategies: [CoverageMatchingStrategy]
    public let message: String

    public init(
        entityID: String?,
        entityDisplayName: String?,
        sourcePath: String?,
        matchedSourcePath: String?,
        matchedFunction: String?,
        availability: CoverageAvailability,
        confidence: CoverageMatchingConfidence,
        attemptedStrategies: [CoverageMatchingStrategy],
        message: String
    ) {
        self.entityID = entityID
        self.entityDisplayName = entityDisplayName
        self.sourcePath = sourcePath
        self.matchedSourcePath = matchedSourcePath
        self.matchedFunction = matchedFunction
        self.availability = availability
        self.confidence = confidence
        self.attemptedStrategies = attemptedStrategies
        self.message = message
    }
}

public struct CoverageMatchingResult: Codable, Equatable, Sendable {
    public let evidence: [DebtEvidence]
    public let diagnostics: [CoverageDiagnostic]

    public init(evidence: [DebtEvidence], diagnostics: [CoverageDiagnostic]) {
        self.evidence = evidence
        self.diagnostics = diagnostics
    }
}
