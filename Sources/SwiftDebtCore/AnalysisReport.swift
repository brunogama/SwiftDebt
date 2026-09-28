public struct AnalysisReport: Codable, Sendable {
    public let schemaVersion: Int
    public let engineVersion: String
    public let typeScope: TypeScope
    public let scoringMode: ScoringMode
    public let complete: Bool
    public let inputFileCount: Int
    public let inputFiles: [String]
    public let minimumDuplicateLines: Int
    public let analyzedFileCount: Int
    public let modules: [String]
    public let codeLineCount: Int
    public let classScopeVariableCount: Int
    public let topLevelVariableCount: Int
    public let methodCount: Int
    public let functionCount: Int
    public let uniqueDuplicatedLineCount: Int
    public let metrics: [MetricSummary]
    public let overallScore: Double?
    public let overallScoreNote: String?
    public let findings: [Finding]
    public let diagnostics: [AnalysisDiagnostic]
    public let couplings: [CouplingEdge]
    public let dependencyGraph: SwiftDependencyGraph
    public let duplicateBlocks: [DuplicateBlock]
    public let debtItems: [DebtItem]

    public var hasViolations: Bool { !findings.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case engineVersion
        case typeScope
        case scoringMode
        case complete
        case inputFileCount
        case inputFiles
        case minimumDuplicateLines
        case analyzedFileCount
        case modules
        case codeLineCount
        case classScopeVariableCount
        case topLevelVariableCount
        case methodCount
        case functionCount
        case uniqueDuplicatedLineCount
        case metrics
        case overallScore
        case overallScoreNote
        case findings
        case diagnostics
        case couplings
        case dependencyGraph
        case duplicateBlocks
        case debtItems
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(engineVersion, forKey: .engineVersion)
        try values.encode(typeScope, forKey: .typeScope)
        try values.encode(scoringMode, forKey: .scoringMode)
        try values.encode(complete, forKey: .complete)
        try values.encode(inputFileCount, forKey: .inputFileCount)
        try values.encode(inputFiles, forKey: .inputFiles)
        try values.encode(minimumDuplicateLines, forKey: .minimumDuplicateLines)
        try values.encode(analyzedFileCount, forKey: .analyzedFileCount)
        try values.encode(modules, forKey: .modules)
        try values.encode(codeLineCount, forKey: .codeLineCount)
        try values.encode(classScopeVariableCount, forKey: .classScopeVariableCount)
        try values.encode(topLevelVariableCount, forKey: .topLevelVariableCount)
        try values.encode(methodCount, forKey: .methodCount)
        try values.encode(functionCount, forKey: .functionCount)
        try values.encode(uniqueDuplicatedLineCount, forKey: .uniqueDuplicatedLineCount)
        try values.encode(metrics, forKey: .metrics)
        try values.encode(overallScore, forKey: .overallScore)
        try values.encode(overallScoreNote, forKey: .overallScoreNote)
        try values.encode(findings, forKey: .findings)
        try values.encode(diagnostics, forKey: .diagnostics)
        try values.encode(couplings, forKey: .couplings)
        try values.encode(dependencyGraph, forKey: .dependencyGraph)
        try values.encode(duplicateBlocks, forKey: .duplicateBlocks)
        try values.encode(debtItems, forKey: .debtItems)
    }
}

extension AnalysisReport {
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        engineVersion = try values.decode(String.self, forKey: .engineVersion)
        typeScope = try values.decode(TypeScope.self, forKey: .typeScope)
        scoringMode = try values.decode(ScoringMode.self, forKey: .scoringMode)
        complete = try values.decode(Bool.self, forKey: .complete)
        inputFileCount = try values.decode(Int.self, forKey: .inputFileCount)
        inputFiles = try values.decode([String].self, forKey: .inputFiles)
        minimumDuplicateLines = try values.decode(Int.self, forKey: .minimumDuplicateLines)
        analyzedFileCount = try values.decode(Int.self, forKey: .analyzedFileCount)
        modules = try values.decode([String].self, forKey: .modules)
        codeLineCount = try values.decode(Int.self, forKey: .codeLineCount)
        classScopeVariableCount = try values.decode(Int.self, forKey: .classScopeVariableCount)
        topLevelVariableCount = try values.decode(Int.self, forKey: .topLevelVariableCount)
        methodCount = try values.decode(Int.self, forKey: .methodCount)
        functionCount = try values.decode(Int.self, forKey: .functionCount)
        uniqueDuplicatedLineCount = try values.decode(Int.self, forKey: .uniqueDuplicatedLineCount)
        metrics = try values.decode([MetricSummary].self, forKey: .metrics)
        overallScore = try values.decodeIfPresent(Double.self, forKey: .overallScore)
        overallScoreNote = try values.decodeIfPresent(String.self, forKey: .overallScoreNote)
        findings = try values.decode([Finding].self, forKey: .findings)
        diagnostics = try values.decode([AnalysisDiagnostic].self, forKey: .diagnostics)
        couplings = try values.decode([CouplingEdge].self, forKey: .couplings)
        dependencyGraph =
            try values.decodeIfPresent(SwiftDependencyGraph.self, forKey: .dependencyGraph)
            ?? Self.emptyDependencyGraph
        duplicateBlocks = try values.decode([DuplicateBlock].self, forKey: .duplicateBlocks)
        debtItems = try values.decode([DebtItem].self, forKey: .debtItems)
    }

    private static let emptyDependencyGraph = SwiftDependencyGraph(
        nodes: [],
        edges: [],
        couplingRisks: [],
        dependencyContexts: [],
        statistics: CallGraphStatistics(
            nodeCount: 0,
            edgeCount: 0,
            resolvedEdgeCount: 0,
            ambiguousEdgeCount: 0,
            unresolvedEdgeCount: 0,
            syntaxOnlyNote: "No dependency graph evidence is available in this legacy report."
        ),
        dot: "digraph SwiftDependencyGraph {\n}\n"
    )
}
// Parser-to-core boundaries are package-visible, not public implementation API.
