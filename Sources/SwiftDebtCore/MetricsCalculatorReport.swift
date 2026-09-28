struct AnalysisReportAssembly {
    let parsed: [ParsedSource]
    let files: [ParsedSource]
    let options: AnalysisOptions
    let complete: Bool
    let propertyCount: Int
    let codeLines: Int
    let methods: [FunctionFacts]
    let functions: [FunctionFacts]
    let duplication: DuplicateDetector.Result
    let scoring: MetricScoringResult
    let overall: Double?
    let diagnostics: [AnalysisDiagnostic]
    let edges: [CouplingEdge]
    let dependencyGraph: SwiftDependencyGraph
    let debtItems: [DebtItem]
}

extension MetricsCalculator {
    func report(_ input: AnalysisReportAssembly) -> AnalysisReport {
        AnalysisReport(
            schemaVersion: 2, engineVersion: SwiftDebtRelease.version,
            typeScope: input.options.typeScope, scoringMode: input.options.scoring,
            complete: input.complete, inputFileCount: input.parsed.count,
            inputFiles: input.parsed.map(\.path).sorted(),
            minimumDuplicateLines: input.options.minimumDuplicateLines,
            analyzedFileCount: input.files.count,
            modules: Set(input.parsed.map(\.module)).sorted(), codeLineCount: input.codeLines,
            classScopeVariableCount: input.propertyCount,
            topLevelVariableCount: input.files.reduce(0) { $0 + $1.topLevelVariables },
            methodCount: input.methods.count, functionCount: input.functions.count,
            uniqueDuplicatedLineCount: input.duplication.uniqueLines,
            metrics: input.scoring.summaries, overallScore: input.overall,
            overallScoreNote: input.overall == nil
                ? "An overall score requires a complete analysis and all ten defined metric scores."
                : nil,
            findings: input.scoring.findings, diagnostics: input.diagnostics,
            couplings: input.edges, dependencyGraph: input.dependencyGraph,
            duplicateBlocks: input.duplication.blocks, debtItems: input.debtItems)
    }
}
