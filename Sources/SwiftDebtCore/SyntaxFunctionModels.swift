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
    package let accessLevel: String?
    package let effectFacts: [SyntaxEffectFact]
    package let compositionFacts: [FunctionalCompositionFact]
    package let callSites: [CallSiteFact]
    package let riskFacts: [SwiftRiskFact]

    package init(
        name: String, kind: CallableKind = .method, owner: TypeKey?, location: SourceLocation,
        codeLines: Int,
        complexity: Int, cognitiveComplexity: Int = 0, maxNestingDepth: Int = 0, parameters: Int,
        bareReferences: Set<String>, explicitSelfReferences: Set<String>,
        shadowedNames: Set<String>,
        accessLevel: String? = nil, effectFacts: [SyntaxEffectFact] = [],
        compositionFacts: [FunctionalCompositionFact] = [], callSites: [CallSiteFact] = [],
        riskFacts: [SwiftRiskFact] = []
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
        self.accessLevel = accessLevel
        self.effectFacts = effectFacts
        self.compositionFacts = compositionFacts
        self.callSites = callSites
        self.riskFacts = riskFacts
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
    package let riskFacts: [SwiftRiskFact]

    package init(
        path: String, module: String, types: [TypeFragment], functions: [FunctionFacts],
        closures: [ClosureFacts] = [], lines: [CodeLine], topLevelVariables: Int,
        diagnostics: [AnalysisDiagnostic], riskFacts: [SwiftRiskFact] = []
    ) {
        self.path = path
        self.module = module
        self.types = types
        self.functions = functions
        self.closures = closures
        self.lines = lines
        self.topLevelVariables = topLevelVariables
        self.diagnostics = diagnostics
        self.riskFacts = riskFacts
    }

    package var isValid: Bool { !diagnostics.contains { $0.severity == .error } }
}

package protocol SourceParsing: Sendable {
    func parse(_ source: SourceUnit) -> ParsedSource
}
