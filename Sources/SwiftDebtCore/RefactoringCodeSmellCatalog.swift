public enum CodeSmellSupportState: String, Codable, Sendable {
    case supported
    case partiallySupported = "partially-supported"
    case research
    case notReliablyObservable = "not-reliably-observable"
}

public struct RefactoringCodeSmell: Codable, Equatable, Sendable {
    public let name: String
    public let supportState: CodeSmellSupportState
    public let ruleIdentity: String?
    public let semanticRevision: UInt?
    public let minimumPredicate: String
    public let requiredEvidence: [String]
    public let optionalEvidence: [String]
    public let scope: String
    public let falsePositiveRisk: String
    public let falseNegativeRisk: String
    public let explanationContract: String
    public let fixtureReferences: [String]

    package init(
        name: String,
        supportState: CodeSmellSupportState,
        ruleIdentity: String? = nil,
        semanticRevision: UInt? = nil,
        minimumPredicate: String,
        requiredEvidence: [String],
        optionalEvidence: [String] = [],
        scope: String,
        falsePositiveRisk: String,
        falseNegativeRisk: String,
        explanationContract: String,
        fixtureReferences: [String] = []
    ) {
        self.name = name
        self.supportState = supportState
        self.ruleIdentity = ruleIdentity
        self.semanticRevision = semanticRevision
        self.minimumPredicate = minimumPredicate
        self.requiredEvidence = requiredEvidence
        self.optionalEvidence = optionalEvidence
        self.scope = scope
        self.falsePositiveRisk = falsePositiveRisk
        self.falseNegativeRisk = falseNegativeRisk
        self.explanationContract = explanationContract
        self.fixtureReferences = fixtureReferences
    }
}

public enum RefactoringCodeSmellCatalog {
    public static let all: [RefactoringCodeSmell] =
        supportedSyntaxSmells + researchSmells + intentDependentSmells

    public static let report = RefactoringCodeSmellCatalogReport(entries: all)

    public static func named(_ name: String) -> RefactoringCodeSmell? {
        all.first { $0.name == name }
    }
}

public struct RefactoringCodeSmellCatalogReport: Codable, Equatable, Sendable {
    public let reportKind: String
    public let schemaVersion: Int
    public let entries: [RefactoringCodeSmell]

    package init(entries: [RefactoringCodeSmell]) {
        reportKind = "swiftdebt-refactoring-code-smells"
        schemaVersion = 1
        self.entries = entries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let reportKind = try container.decode(String.self, forKey: .reportKind)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard reportKind == "swiftdebt-refactoring-code-smells", schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported refactoring code smell catalog kind or schema."
            )
        }
        self.reportKind = reportKind
        self.schemaVersion = schemaVersion
        entries = try container.decode([RefactoringCodeSmell].self, forKey: .entries)
    }
}
