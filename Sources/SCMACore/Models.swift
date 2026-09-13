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
        dependencyGraph = try values.decodeIfPresent(SwiftDependencyGraph.self, forKey: .dependencyGraph)
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
package struct TypeKey: Hashable, Sendable {
    package let module: String
    package let name: String
    package var displayName: String { "\(module).\(name)" }

    package init(module: String, name: String) {
        self.module = module
        self.name = name
    }
}

package struct TypeFragment: Sendable {
    package let key: TypeKey
    package let kind: String
    package let isExtension: Bool
    package let location: SourceLocation
    package let codeLines: Int
    package let propertyNames: Set<String>
    package let referencedTypes: Set<String>
    package let importedModules: Set<String>

    package init(
        key: TypeKey, kind: String, isExtension: Bool, location: SourceLocation,
        codeLines: Int, propertyNames: Set<String>, referencedTypes: Set<String>,
        importedModules: Set<String> = []
    ) {
        self.key = key
        self.kind = kind
        self.isExtension = isExtension
        self.location = location
        self.codeLines = codeLines
        self.propertyNames = propertyNames
        self.referencedTypes = referencedTypes
        self.importedModules = importedModules
    }
}

package enum CallableKind: Sendable {
    /// `func`, `init`, `deinit`.
    case method
    /// Property or subscript accessor body (`get`, `set`, `willSet`, `didSet`, ...).
    case accessor
}

package enum SyntaxEvidenceConfidence: String, Codable, Sendable {
    case measuredSyntax
    case heuristic
}

package enum SyntaxEffectCategory: String, Codable, CaseIterable, Sendable {
    case mutation
    case inoutMutation
    case propertyWrite
    case globalOrStaticState
    case asyncEffect
    case throwingEffect
    case closureEffect
}

package struct SyntaxEffectFact: Codable, Hashable, Sendable {
    package let category: SyntaxEffectCategory
    package let detail: String
    package let location: SourceLocation
    package let confidence: SyntaxEvidenceConfidence
    package let inClosure: Bool

    package init(
        category: SyntaxEffectCategory,
        detail: String,
        location: SourceLocation,
        confidence: SyntaxEvidenceConfidence = .measuredSyntax,
        inClosure: Bool = false
    ) {
        self.category = category
        self.detail = detail
        self.location = location
        self.confidence = confidence
        self.inClosure = inClosure
    }
}

package struct FunctionalCompositionFact: Codable, Hashable, Sendable {
    package let operation: String
    package let location: SourceLocation
    package let closureHasSideEffects: Bool
    package let confidence: SyntaxEvidenceConfidence

    package init(
        operation: String,
        location: SourceLocation,
        closureHasSideEffects: Bool,
        confidence: SyntaxEvidenceConfidence = .measuredSyntax
    ) {
        self.operation = operation
        self.location = location
        self.closureHasSideEffects = closureHasSideEffects
        self.confidence = confidence
    }
}

package struct FunctionFacts: Sendable {
    package let name: String
    package let kind: CallableKind
    package let owner: TypeKey?
    package let location: SourceLocation
    package let codeLines: Int
    package let complexity: Int
    package let cognitiveComplexity: Int
    package let maxNestingDepth: Int
    package let parameters: Int
    /// Bare identifiers that were not shadowed by a lexically enclosing local binding.
    package let bareReferences: Set<String>
    package let explicitSelfReferences: Set<String>
    /// Every local binding name seen anywhere in the body; informational.
    package let shadowedNames: Set<String>
    package let effectFacts: [SyntaxEffectFact]
    package let compositionFacts: [FunctionalCompositionFact]
    package let callSites: [CallSiteFact]

    package init(
        name: String, kind: CallableKind = .method, owner: TypeKey?, location: SourceLocation, codeLines: Int,
        complexity: Int, cognitiveComplexity: Int = 0, maxNestingDepth: Int = 0, parameters: Int,
        bareReferences: Set<String>, explicitSelfReferences: Set<String>, shadowedNames: Set<String>,
        effectFacts: [SyntaxEffectFact] = [], compositionFacts: [FunctionalCompositionFact] = [],
        callSites: [CallSiteFact] = []
    ) {
        self.name = name
        self.kind = kind
        self.owner = owner
        self.location = location
        self.codeLines = codeLines
        self.complexity = complexity
        self.cognitiveComplexity = cognitiveComplexity
        self.maxNestingDepth = maxNestingDepth
        self.parameters = parameters
        self.bareReferences = bareReferences
        self.explicitSelfReferences = explicitSelfReferences
        self.shadowedNames = shadowedNames
        self.effectFacts = effectFacts
        self.compositionFacts = compositionFacts
        self.callSites = callSites
    }
}

package struct ClosureFacts: Sendable {
    package let owner: TypeKey?
    package let location: SourceLocation
    package let codeLines: Int
    package let complexity: Int
    package let cognitiveComplexity: Int
    package let maxNestingDepth: Int
    package let parameters: Int

    package init(
        owner: TypeKey?, location: SourceLocation, codeLines: Int, complexity: Int,
        cognitiveComplexity: Int, maxNestingDepth: Int, parameters: Int
    ) {
        self.owner = owner
        self.location = location
        self.codeLines = codeLines
        self.complexity = complexity
        self.cognitiveComplexity = cognitiveComplexity
        self.maxNestingDepth = maxNestingDepth
        self.parameters = parameters
    }
}

package struct CodeLine: Sendable {
    package let number: Int
    package let signature: String
    package init(number: Int, signature: String) {
        self.number = number
        self.signature = signature
    }
}

package struct ParsedSource: Sendable {
    package let path: String
    package let module: String
    package let types: [TypeFragment]
    package let functions: [FunctionFacts]
    package let closures: [ClosureFacts]
    package let lines: [CodeLine]
    package let topLevelVariables: Int
    package let diagnostics: [AnalysisDiagnostic]

    package init(
        path: String, module: String, types: [TypeFragment], functions: [FunctionFacts],
        closures: [ClosureFacts] = [], lines: [CodeLine], topLevelVariables: Int,
        diagnostics: [AnalysisDiagnostic]
    ) {
        self.path = path
        self.module = module
        self.types = types
        self.functions = functions
        self.closures = closures
        self.lines = lines
        self.topLevelVariables = topLevelVariables
        self.diagnostics = diagnostics
    }

    package var isValid: Bool { !diagnostics.contains { $0.severity == .error } }
}

package protocol SourceParsing: Sendable {
    func parse(_ source: SourceUnit) -> ParsedSource
}
