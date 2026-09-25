public struct DetectionLocation: Equatable, Hashable, Sendable {
    public let sourcePath: SourcePath
    public let line: Int
    public let column: Int

    package init(sourcePath: SourcePath, line: Int, column: Int) {
        self.sourcePath = sourcePath
        self.line = line
        self.column = column
    }
}

public struct Detection: Equatable, Sendable {
    public let ruleIdentity: RuleIdentity
    public let semanticRevision: SemanticRevision
    public let severity: RuleSeverity
    public let location: DetectionLocation
    public let message: String
    public let structuralEvidence: DetectionStructuralEvidence

    package init(
        ruleIdentity: RuleIdentity,
        semanticRevision: SemanticRevision,
        severity: RuleSeverity,
        location: DetectionLocation,
        message: String,
        structuralEvidence: DetectionStructuralEvidence
    ) {
        self.ruleIdentity = ruleIdentity
        self.semanticRevision = semanticRevision
        self.severity = severity
        self.location = location
        self.message = message
        self.structuralEvidence = structuralEvidence
    }
}

public enum RuleAnalysisOutcome: Equatable, Sendable {
    case committed([Detection])
    case parseFailed(diagnostics: [AnalysisDiagnostic])
    case unsupported(reason: String)
    case failed(reason: String)
}

public struct RuleAnalysisResult: Equatable, Sendable {
    public let descriptor: RuleDescriptor
    public let sourcePath: SourcePath
    public let outcome: RuleAnalysisOutcome

    package init(
        descriptor: RuleDescriptor,
        sourcePath: SourcePath,
        outcome: RuleAnalysisOutcome
    ) {
        self.descriptor = descriptor
        self.sourcePath = sourcePath
        self.outcome = outcome
    }

    public var isCommitted: Bool {
        if case .committed = outcome { return true }
        return false
    }

    public var detections: [Detection] {
        if case .committed(let detections) = outcome { return detections }
        return []
    }

    /// An empty committed result proves absence for this rule and source snapshot.
    public var provesAbsence: Bool { isCommitted && detections.isEmpty }
}

public struct AnalysisSnapshot: Equatable, Sendable {
    public let ruleDescriptors: [RuleDescriptor]
    public let selectedSourcePaths: [SourcePath]
    public let ruleResults: [RuleAnalysisResult]

    package init(
        ruleDescriptors: [RuleDescriptor],
        selectedSourcePaths: [SourcePath],
        ruleResults: [RuleAnalysisResult]
    ) {
        self.ruleDescriptors = ruleDescriptors
        self.selectedSourcePaths = selectedSourcePaths
        self.ruleResults = ruleResults
    }

    public var isComplete: Bool {
        guard
            !ruleDescriptors.isEmpty,
            Set(ruleDescriptors.map(\.identity)).count == ruleDescriptors.count,
            Set(selectedSourcePaths).count == selectedSourcePaths.count
        else { return false }

        let expectedPairs = ruleDescriptors.flatMap { descriptor in
            selectedSourcePaths.map { sourcePath in (descriptor, sourcePath) }
        }
        guard expectedPairs.count == ruleResults.count else { return false }
        return zip(expectedPairs, ruleResults).allSatisfy { expected, result in
            expected.0 == result.descriptor
                && expected.1 == result.sourcePath
                && result.isCommitted
        }
    }

    public var detections: [Detection] { ruleResults.flatMap(\.detections) }
}
