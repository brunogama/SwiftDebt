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
        precondition(Self.validRuleReference(identity: ruleIdentity, revision: semanticRevision))
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

    private enum CodingKeys: String, CodingKey {
        case name, supportState, ruleIdentity, semanticRevision, minimumPredicate
        case requiredEvidence, optionalEvidence, scope, falsePositiveRisk, falseNegativeRisk
        case explanationContract, fixtureReferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try container.decodeIfPresent(String.self, forKey: .ruleIdentity)
        let revision = try container.decodeIfPresent(UInt.self, forKey: .semanticRevision)
        guard Self.validRuleReference(identity: identity, revision: revision) else {
            throw DecodingError.dataCorruptedError(
                forKey: .ruleIdentity,
                in: container,
                debugDescription: "Rule identity and positive semantic revision must be valid together."
            )
        }
        name = try container.decode(String.self, forKey: .name)
        supportState = try container.decode(CodeSmellSupportState.self, forKey: .supportState)
        ruleIdentity = identity
        semanticRevision = revision
        minimumPredicate = try container.decode(String.self, forKey: .minimumPredicate)
        requiredEvidence = try container.decode([String].self, forKey: .requiredEvidence)
        optionalEvidence = try container.decode([String].self, forKey: .optionalEvidence)
        scope = try container.decode(String.self, forKey: .scope)
        falsePositiveRisk = try container.decode(String.self, forKey: .falsePositiveRisk)
        falseNegativeRisk = try container.decode(String.self, forKey: .falseNegativeRisk)
        explanationContract = try container.decode(String.self, forKey: .explanationContract)
        fixtureReferences = try container.decode([String].self, forKey: .fixtureReferences)
    }

    private static func validRuleReference(identity: String?, revision: UInt?) -> Bool {
        if identity == nil && revision == nil { return true }
        guard let identity, let revision, SemanticRevision(revision) != nil else { return false }
        let parts = identity.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2, let id = parts.last else { return false }
        let namespace = parts.dropLast().joined(separator: ".")
        return RuleNamespace(namespace) != nil && RuleID(String(id)) != nil
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
        guard entries == RefactoringCodeSmellCatalog.all else {
            throw DecodingError.dataCorruptedError(
                forKey: .entries,
                in: container,
                debugDescription: "Catalog entries do not match this schema's canonical Fowler catalog."
            )
        }
    }
}
