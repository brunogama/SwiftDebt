public enum RepositoryEvidenceClass: String, Codable, CaseIterable, Sendable {
    case syntax
    case metric
    case structural
    case relationship
    case compilerBacked = "compiler-backed"
    case similarity
}

public enum RepositoryAnalysisUnitKind: String, Codable, Sendable {
    case functionParameters = "function-parameters"
    case initializerParameters = "initializer-parameters"
    case subscriptParameters = "subscript-parameters"
    case nominalProperties = "nominal-properties"
    case switchStatement = "switch-statement"
}

public struct RepositoryComparedUnit: Codable, Equatable, Hashable, Sendable {
    public let kind: RepositoryAnalysisUnitKind
    public let displayName: String
    public let location: SourceLocation

    package init(kind: RepositoryAnalysisUnitKind, displayName: String, location: SourceLocation) {
        self.kind = kind
        self.displayName = displayName
        self.location = location
    }
}

public struct RepositoryObservedFact: Codable, Equatable, Sendable {
    public let kind: String
    public let value: String
    public let evidenceClass: RepositoryEvidenceClass
    public let locations: [SourceLocation]

    package init(
        kind: String,
        value: String,
        evidenceClass: RepositoryEvidenceClass,
        locations: [SourceLocation]
    ) {
        self.kind = kind
        self.value = value
        self.evidenceClass = evidenceClass
        self.locations = locations.sorted(by: repositorySourceLocationOrder)
    }
}

public struct RepositoryDetectionSelector: Codable, Equatable, Hashable, Sendable {
    public let ruleIdentity: String
    public let semanticRevision: UInt
    public let snapshotDigest: RepositoryDigest
    public let location: SourceLocation
    public let evidenceFingerprint: RepositoryDigest

    package init(
        ruleIdentity: String,
        semanticRevision: UInt,
        snapshotDigest: RepositoryDigest,
        location: SourceLocation,
        evidenceFingerprint: RepositoryDigest
    ) {
        self.ruleIdentity = ruleIdentity
        self.semanticRevision = semanticRevision
        self.snapshotDigest = snapshotDigest
        self.location = location
        self.evidenceFingerprint = evidenceFingerprint
    }
}

public struct RepositoryDetectionExplanation: Codable, Equatable, Sendable {
    public let predicate: String
    public let decisiveFacts: [RepositoryObservedFact]
    public let comparedUnits: [RepositoryComparedUnit]
    public let evidenceClasses: [RepositoryEvidenceClass]
    public let limitations: [String]
    public let refactoringDirection: String
    public let documentationURL: String

    package init(
        predicate: String,
        decisiveFacts: [RepositoryObservedFact],
        comparedUnits: [RepositoryComparedUnit],
        evidenceClasses: [RepositoryEvidenceClass],
        limitations: [String],
        refactoringDirection: String,
        documentationURL: String
    ) {
        self.predicate = predicate
        self.decisiveFacts = decisiveFacts.sorted(by: repositoryObservedFactOrder)
        self.comparedUnits = comparedUnits.sorted(by: repositoryComparedUnitOrder)
        self.evidenceClasses = evidenceClasses.sorted(by: repositoryEvidenceClassOrder)
        self.limitations = limitations
        self.refactoringDirection = refactoringDirection
        self.documentationURL = documentationURL
    }
}

public struct RepositoryDetection: Codable, Equatable, Sendable {
    public let selector: RepositoryDetectionSelector
    public let title: String
    public let primaryLocation: SourceLocation
    public let summary: String
    public let explanation: RepositoryDetectionExplanation

    package init(
        selector: RepositoryDetectionSelector,
        title: String,
        primaryLocation: SourceLocation,
        summary: String,
        explanation: RepositoryDetectionExplanation
    ) {
        self.selector = selector
        self.title = title
        self.primaryLocation = primaryLocation
        self.summary = summary
        self.explanation = explanation
    }
}
