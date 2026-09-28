struct MetricObservationInput {
    let types: [TypeKey: MetricsCalculator.Aggregate]
    let ownedByType: [TypeKey: [FunctionFacts]]
    let functions: [FunctionFacts]
    let couplingCounts: [String: Int]
    let duplicateBlocks: [DuplicateBlock]
}

struct MetricScoringResult {
    let summaries: [MetricSummary]
    let findings: [Finding]
}

struct StructuralAnalysis {
    let files: [ParsedSource]
    var diagnostics: [AnalysisDiagnostic]
    let types: [TypeKey: MetricsCalculator.Aggregate]
    let functions: [FunctionFacts]
    let ownedByType: [TypeKey: [FunctionFacts]]
    let methods: [FunctionFacts]
    let edges: [CouplingEdge]
    let couplingCounts: [String: Int]
    let dependencyGraph: SwiftDependencyGraph
    let duplication: DuplicateDetector.Result
    let debtItems: [DebtItem]
}

extension MetricsCalculator {
    func structuralAnalysis(
        parsed: [ParsedSource], options: AnalysisOptions,
        phaseSink: (any AnalysisPhaseSink)?
    ) throws -> StructuralAnalysis {
        phaseSink?.begin(.structuralEvidence)
        let files = parsed.filter(\.isValid).sorted { $0.path < $1.path }
        var diagnostics = diagnostics(for: parsed, strictSyntax: options.strictSyntax)
        let types = aggregate(
            files.flatMap(\.types), scope: options.typeScope, diagnostics: &diagnostics)
        let functions = files.flatMap(\.functions).sorted {
            locationOrder($0.location, $1.location)
        }
        let owned = functions.filter { $0.owner.flatMap { types[$0] } != nil }
        let ownedByType = Dictionary(grouping: owned, by: { $0.owner! })
        let methods = owned.filter { $0.kind == .method }
        let edges = couplingEdges(types)
        let couplingCounts = couplingCounts(edges)
        let graph = dependencyGraph(files: files, options: options, phaseSink: phaseSink)
        let duplication = try DuplicateDetector().detect(files, options: options)
        let structuralItems = StructuralDebtBuilder().items(
            files: files, types: structuralTypes(types, ownedByType: ownedByType),
            functions: functions, duplicateBlocks: duplication.blocks)
        phaseSink?.end(.structuralEvidence)
        let debtItems = enrichedDebtItems(
            structuralItems: structuralItems, files: files, graph: graph, phaseSink: phaseSink)
        return StructuralAnalysis(
            files: files, diagnostics: diagnostics, types: types, functions: functions,
            ownedByType: ownedByType, methods: methods, edges: edges,
            couplingCounts: couplingCounts, dependencyGraph: graph, duplication: duplication,
            debtItems: debtItems)
    }

    private func couplingCounts(_ edges: [CouplingEdge]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for edge in edges {
            counts[edge.first, default: 0] += 1
            counts[edge.second, default: 0] += 1
        }
        return counts
    }

    private func dependencyGraph(
        files: [ParsedSource], options: AnalysisOptions,
        phaseSink: (any AnalysisPhaseSink)?
    ) -> SwiftDependencyGraph {
        phaseSink?.begin(.graph)
        defer { phaseSink?.end(.graph) }
        return DependencyGraphBuilder().build(from: files, typeScope: options.typeScope)
    }

    private func enrichedDebtItems(
        structuralItems: [DebtItem], files: [ParsedSource], graph: SwiftDependencyGraph,
        phaseSink: (any AnalysisPhaseSink)?
    ) -> [DebtItem] {
        phaseSink?.begin(.functionalEvidence)
        let functionalEvidence = DebtFunctionalEvidenceBuilder().evidence(for: files)
        phaseSink?.end(.functionalEvidence)
        phaseSink?.begin(.aggregation)
        defer { phaseSink?.end(.aggregation) }
        return enrichDebtItems(
            structuralItems, functionalEvidence: functionalEvidence,
            dependencyContexts: graph.dependencyContexts)
    }

    func diagnostics(for parsed: [ParsedSource], strictSyntax: Bool) -> [AnalysisDiagnostic] {
        parsed.flatMap { file -> [AnalysisDiagnostic] in
            guard !file.isValid, !strictSyntax else { return file.diagnostics }
            return file.diagnostics.map {
                $0.severity == .error
                    ? AnalysisDiagnostic(
                        severity: .warning, message: "File skipped (parse error): \($0.message)",
                        location: $0.location)
                    : $0
            }
        }
    }

    func structuralTypes(
        _ types: [TypeKey: Aggregate], ownedByType: [TypeKey: [FunctionFacts]]
    ) -> [StructuralTypeFacts] {
        types.values.map { type in
            let owned = ownedByType[type.key, default: []]
            return StructuralTypeFacts(
                key: type.key, location: type.location, codeLines: type.lines,
                propertyCount: type.fields.count,
                methodCount: owned.filter { $0.kind == .method }.count,
                weightedMethodComplexity: owned.reduce(0) { $0 + $1.complexity },
                callableNames: owned.map(\.name).sorted())
        }
    }

    func metricObservations(_ input: MetricObservationInput) -> [Metric: [MetricObservation]] {
        var observations: [Metric: [MetricObservation]] = [:]
        for type in input.types.values.sorted(by: { $0.key.displayName < $1.key.displayName }) {
            let owned = input.ownedByType[type.key, default: []]
            let values: [(Metric, Int)] = [
                (.locc, type.lines), (.wmcc, owned.reduce(0) { $0 + $1.complexity }),
                (.nomc, owned.filter { $0.kind == .method }.count), (.nogc, type.fields.count),
                (.nocc, input.couplingCounts[type.key.displayName, default: 0]),
            ]
            appendTypeObservations(
                values, type: type, ownedFunctions: owned, to: &observations)
        }
        for function in input.functions {
            for (metric, value) in [
                (Metric.locf, function.codeLines), (.ccf, function.complexity),
                (.nopf, function.parameters),
            ] {
                observations[metric, default: []].append(
                    MetricObservation(
                        entity: function.name, location: function.location, value: value))
            }
        }
        for block in input.duplicateBlocks {
            let other = "\(block.second.file):\(block.second.startLine)-\(block.second.endLine)"
            observations[.dc, default: []].append(
                MetricObservation(
                    entity: "duplicate of \(other)",
                    location: SourceLocation(file: block.first.file, line: block.first.startLine),
                    value: block.first.codeLines))
        }
        return observations
    }

    private func appendTypeObservations(
        _ values: [(Metric, Int)], type: Aggregate, ownedFunctions: [FunctionFacts],
        to observations: inout [Metric: [MetricObservation]]
    ) {
        for (metric, value) in values {
            observations[metric, default: []].append(
                MetricObservation(
                    entity: type.key.displayName, location: type.location, value: value))
        }
        for method in ownedFunctions {
            let references = method.explicitSelfReferences.union(method.bareReferences)
                .intersection(type.fields)
            observations[.noav, default: []].append(
                MetricObservation(
                    entity: method.name, location: method.location, value: references.count))
        }
    }

    func metricSummaries(
        observations: [Metric: [MetricObservation]], options: AnalysisOptions,
        complete: Bool, scoreInputs: ScoreInputs
    ) -> MetricScoringResult {
        var findings: [Finding] = []
        let summaries = Metric.allCases.map { metric in
            let items = observations[metric, default: []].sorted {
                if $0.location != $1.location { return locationOrder($0.location, $1.location) }
                return $0.entity < $1.entity
            }
            let threshold = options.threshold(for: metric)
            if let threshold {
                findings += items.filter { $0.value > threshold }.map {
                    Finding(
                        metric: metric, entity: $0.entity, location: $0.location, value: $0.value,
                        threshold: threshold)
                }
            }
            let values = items.map(\.value)
            let result = PaperScoring().score(
                metric: metric, values: values, inputs: scoreInputs, mode: options.scoring)
            return MetricSummary(
                metric: metric, observations: items, threshold: threshold,
                violations: threshold.map { limit in values.filter { $0 > limit }.count } ?? 0,
                paperViolations: metric.paperThreshold.map { limit in
                    values.filter { $0 > limit }.count
                },
                maximum: values.max(), total: values.reduce(0, +),
                score: complete ? result.value : nil,
                scoreNote: complete ? result.note : "Analysis incomplete; score withheld.",
                measurementNote: measurementNote(metric))
        }
        return MetricScoringResult(summaries: summaries, findings: findings)
    }
}
