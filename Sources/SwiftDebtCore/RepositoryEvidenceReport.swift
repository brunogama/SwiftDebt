public enum RepositoryEvidenceReportSchema {
    public static let currentVersion = 1
    public static let reportKind = "swiftdebt-repository-evidence"
}

public struct RepositorySnapshotIdentity: Codable, Equatable, Sendable {
    public let sourceFiles: [String]
    public let contentDigest: RepositoryDigest
    public let configuration: RepositoryAnalysisConfiguration
    public let versionControl: RepositoryVersionControlIdentity?

    package init(
        sourceFiles: [String],
        contentDigest: RepositoryDigest,
        configuration: RepositoryAnalysisConfiguration,
        versionControl: RepositoryVersionControlIdentity?
    ) {
        self.sourceFiles = sourceFiles
        self.contentDigest = contentDigest
        self.configuration = configuration
        self.versionControl = versionControl
    }
}

public enum RepositoryRuleCompletionState: String, Codable, Sendable {
    case complete
    case incomplete
}

public enum RepositoryRuleQualification: String, Codable, Sendable {
    case research = "Research"
}

public struct RepositoryRuleEvidence: Codable, Equatable, Sendable {
    public let ruleIdentity: String
    public let semanticRevision: UInt
    public let name: String
    public let qualification: RepositoryRuleQualification
    public let completionState: RepositoryRuleCompletionState
    public let predicate: String
    public let capabilities: [RepositoryCapabilityEvidence]
    public let detections: [RepositoryDetection]
    public let issues: [RepositoryEvidenceIssue]

    package init(
        ruleIdentity: String,
        semanticRevision: UInt,
        name: String,
        qualification: RepositoryRuleQualification = .research,
        completionState: RepositoryRuleCompletionState,
        predicate: String,
        capabilities: [RepositoryCapabilityEvidence],
        detections: [RepositoryDetection],
        issues: [RepositoryEvidenceIssue]
    ) {
        self.ruleIdentity = ruleIdentity
        self.semanticRevision = semanticRevision
        self.name = name
        self.qualification = qualification
        self.completionState = completionState
        self.predicate = predicate
        self.capabilities = capabilities
        self.detections = detections
        self.issues = issues
    }

    public var provesAbsence: Bool {
        completionState == .complete
            && capabilities.allSatisfy { $0.state == .available }
            && detections.isEmpty
    }
}

public struct RepositoryEvidenceSummary: Codable, Equatable, Sendable {
    public let sourceFileCount: Int
    public let completeRuleCount: Int
    public let incompleteRuleCount: Int
    public let detectionCount: Int
    public let currentSnapshotNotice: String

    package init(
        sourceFileCount: Int,
        completeRuleCount: Int,
        incompleteRuleCount: Int,
        detectionCount: Int,
        currentSnapshotNotice: String
    ) {
        self.sourceFileCount = sourceFileCount
        self.completeRuleCount = completeRuleCount
        self.incompleteRuleCount = incompleteRuleCount
        self.detectionCount = detectionCount
        self.currentSnapshotNotice = currentSnapshotNotice
    }
}

public struct RepositoryEvidenceReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let generator: String
    public let snapshot: RepositorySnapshotIdentity
    public let rules: [RepositoryRuleEvidence]
    public let diagnostics: [AnalysisDiagnostic]
    public let summary: RepositoryEvidenceSummary

    package init(
        generator: String,
        snapshot: RepositorySnapshotIdentity,
        rules: [RepositoryRuleEvidence],
        diagnostics: [AnalysisDiagnostic],
        summary: RepositoryEvidenceSummary
    ) {
        schemaVersion = RepositoryEvidenceReportSchema.currentVersion
        reportKind = RepositoryEvidenceReportSchema.reportKind
        self.generator = generator
        self.snapshot = snapshot
        self.rules = rules
        self.diagnostics = diagnostics
        self.summary = summary
    }

    public var isComplete: Bool {
        rules.allSatisfy { $0.completionState == .complete }
    }

    public var detections: [RepositoryDetection] {
        rules.flatMap(\.detections)
    }

    public func detection(for selector: RepositoryDetectionSelector) -> RepositoryDetection? {
        detections.first { $0.selector == selector }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reportKind
        case generator
        case snapshot
        case rules
        case diagnostics
        case summary
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == RepositoryEvidenceReportSchema.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: RepositoryEvidenceContractError.unsupportedSchemaVersion(schemaVersion).description
            )
        }
        let reportKind = try values.decode(String.self, forKey: .reportKind)
        guard reportKind == RepositoryEvidenceReportSchema.reportKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .reportKind,
                in: values,
                debugDescription: RepositoryEvidenceContractError.unsupportedReportKind(reportKind).description
            )
        }
        self.schemaVersion = schemaVersion
        self.reportKind = reportKind
        generator = try values.decode(String.self, forKey: .generator)
        snapshot = try values.decode(RepositorySnapshotIdentity.self, forKey: .snapshot)
        rules = try values.decode([RepositoryRuleEvidence].self, forKey: .rules)
        diagnostics = try values.decode([AnalysisDiagnostic].self, forKey: .diagnostics)
        summary = try values.decode(RepositoryEvidenceSummary.self, forKey: .summary)
    }
}
