package struct MetricsCalculator {
    package init() {}
    package struct Aggregate {
        let key: TypeKey
        let location: SourceLocation
        let lines: Int
        let fields: Set<String>
        let fragments: [TypeFragment]
    }

    package func analyze(
        _ parsed: [ParsedSource], options: AnalysisOptions,
        phaseSink: (any AnalysisPhaseSink)? = nil
    ) throws -> AnalysisReport {
        try options.validate()
        guard !parsed.isEmpty else { throw AnalysisFailure.noSources }
        var analysis = try structuralAnalysis(
            parsed: parsed, options: options, phaseSink: phaseSink)
        let observations = metricObservations(
            MetricObservationInput(
                types: analysis.types, ownedByType: analysis.ownedByType,
                functions: analysis.functions, couplingCounts: analysis.couplingCounts,
                duplicateBlocks: analysis.duplication.blocks))
        let complete = !analysis.diagnostics.contains { $0.severity == .error }
        let propertyCount = analysis.types.values.reduce(0) { $0 + $1.fields.count }
        let codeLines = analysis.files.reduce(0) { $0 + $1.lines.count }
        let scoreInputs = ScoreInputs(
            methodCount: analysis.methods.count, propertyCount: propertyCount,
            parameterCount: analysis.functions.reduce(0) { $0 + $1.parameters },
            duplicateLines: analysis.duplication.uniqueLines, totalLines: codeLines
        )
        phaseSink?.begin(.scoring)
        let scoring = metricSummaries(
            observations: observations, options: options, complete: complete,
            scoreInputs: scoreInputs)
        phaseSink?.end(.scoring)
        let summaries = scoring.summaries
        let scores = summaries.compactMap(\.score)
        let overall =
            complete && scores.count == Metric.allCases.count
            ? scores.reduce(0, +) / Double(scores.count) : nil
        analysis.diagnostics.sort { lhs, rhs in
            if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
            return lhs.message < rhs.message
        }
        return report(
            AnalysisReportAssembly(
                parsed: parsed, files: analysis.files, options: options, complete: complete,
                propertyCount: propertyCount, codeLines: codeLines, methods: analysis.methods,
                functions: analysis.functions, duplication: analysis.duplication, scoring: scoring,
                overall: overall, diagnostics: analysis.diagnostics, edges: analysis.edges,
                dependencyGraph: analysis.dependencyGraph, debtItems: analysis.debtItems))
    }

}

package func locationOrder(_ lhs: SourceLocation, _ rhs: SourceLocation) -> Bool {
    if lhs.file != rhs.file { return lhs.file < rhs.file }
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    return lhs.column < rhs.column
}
