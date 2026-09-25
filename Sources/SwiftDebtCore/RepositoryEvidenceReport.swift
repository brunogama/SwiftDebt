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

public struct RepositoryRuleEvidence: Equatable, Sendable {
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
        semanticRevision > 0
            && completionState == .complete
            && !capabilities.isEmpty
            && capabilities.allSatisfy { $0.state == .available }
            && detections.isEmpty
            && issues.isEmpty
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

public struct RepositoryEvidenceReport: Equatable, Sendable {
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
        !rules.isEmpty && rules.allSatisfy { $0.completionState == .complete }
    }

    public var detections: [RepositoryDetection] {
        rules.flatMap(\.detections)
    }

    public func detection(for selector: RepositoryDetectionSelector) -> RepositoryDetection? {
        detections.first { $0.selector == selector }
    }

}
