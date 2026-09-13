package struct MetricsCalculator {
    package init() {}
    private struct Aggregate {
        let key: TypeKey
        let location: SourceLocation
        let lines: Int
        let fields: Set<String>
        let fragments: [TypeFragment]
    }

    package func analyze(_ parsed: [ParsedSource], options: AnalysisOptions) throws -> AnalysisReport {
        try options.validate()
        guard !parsed.isEmpty else { throw AnalysisFailure.noSources }
        let files = parsed.filter(\.isValid).sorted { $0.path < $1.path }
        var diagnostics = parsed.flatMap { file -> [AnalysisDiagnostic] in
            guard !file.isValid, !options.strictSyntax else { return file.diagnostics }
            // Non-strict mode: the file is skipped, not silently measured, and the report stays complete.
            return file.diagnostics.map {
                $0.severity == .error
                    ? AnalysisDiagnostic(
                        severity: .warning, message: "File skipped (parse error): \($0.message)", location: $0.location)
                    : $0
            }
        }
        let types = aggregate(files.flatMap(\.types), scope: options.typeScope, diagnostics: &diagnostics)
        let functions = files.flatMap(\.functions).sorted { locationOrder($0.location, $1.location) }
        let owned = functions.filter { $0.owner.flatMap { types[$0] } != nil }
        let ownedByType = Dictionary(grouping: owned, by: { $0.owner! })
        // NOMC counts methods only; WMCC and NOAV also see accessor bodies.
        let methods = owned.filter { $0.kind == .method }
        let edges = couplingEdges(types)
        var couplingCounts: [String: Int] = [:]
        for edge in edges {
            couplingCounts[edge.first, default: 0] += 1
            couplingCounts[edge.second, default: 0] += 1
        }
        let duplication = try DuplicateDetector().detect(files, options: options)
        let structuralTypes = types.values.map { type in
            let owned = ownedByType[type.key, default: []]
            return StructuralTypeFacts(
                key: type.key,
                location: type.location,
                codeLines: type.lines,
                propertyCount: type.fields.count,
                methodCount: owned.filter { $0.kind == .method }.count,
                weightedMethodComplexity: owned.reduce(0) { $0 + $1.complexity },
                callableNames: owned.map(\.name).sorted()
            )
        }
        let debtItems = StructuralDebtBuilder().items(
            files: files,
            types: structuralTypes,
            functions: functions,
            duplicateBlocks: duplication.blocks
        )
        var observations: [Metric: [MetricObservation]] = [:]
        for type in types.values.sorted(by: { $0.key.displayName < $1.key.displayName }) {
            let owned = ownedByType[type.key, default: []]
            let values: [(Metric, Int)] = [
                (.locc, type.lines), (.wmcc, owned.reduce(0) { $0 + $1.complexity }),
                (.nomc, owned.filter { $0.kind == .method }.count), (.nogc, type.fields.count),
                (.nocc, couplingCounts[type.key.displayName, default: 0]),
            ]
            for (metric, value) in values {
                observations[metric, default: []].append(
                    MetricObservation(entity: type.key.displayName, location: type.location, value: value)
                )
            }
            for method in owned {
                let references = method.explicitSelfReferences.union(method.bareReferences)
                    .intersection(type.fields)
                observations[.noav, default: []].append(
                    MetricObservation(entity: method.name, location: method.location, value: references.count)
                )
            }
        }
        for function in functions {
            for (metric, value) in [
                (Metric.locf, function.codeLines), (.ccf, function.complexity), (.nopf, function.parameters),
            ] {
                observations[metric, default: []].append(
                    MetricObservation(entity: function.name, location: function.location, value: value)
                )
            }
        }
        for block in duplication.blocks {
            let other = "\(block.second.file):\(block.second.startLine)-\(block.second.endLine)"
            observations[.dc, default: []].append(
                MetricObservation(
                    entity: "duplicate of \(other)",
                    location: SourceLocation(file: block.first.file, line: block.first.startLine),
                    value: block.first.codeLines)
            )
        }
        let complete = !diagnostics.contains { $0.severity == .error }
        let propertyCount = types.values.reduce(0) { $0 + $1.fields.count }
        let codeLines = files.reduce(0) { $0 + $1.lines.count }
        let scoreInputs = ScoreInputs(
            methodCount: methods.count, propertyCount: propertyCount,
            parameterCount: functions.reduce(0) { $0 + $1.parameters },
            duplicateLines: duplication.uniqueLines, totalLines: codeLines
        )
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
                        metric: metric, entity: $0.entity, location: $0.location, value: $0.value, threshold: threshold)
                }
            }
            let values = items.map(\.value)
            let result = PaperScoring().score(
                metric: metric, values: values, inputs: scoreInputs, mode: options.scoring)
            return MetricSummary(
                metric: metric, observations: items, threshold: threshold,
                violations: threshold.map { limit in values.filter { $0 > limit }.count } ?? 0,
                paperViolations: metric.paperThreshold.map { limit in values.filter { $0 > limit }.count },
                maximum: values.max(), total: values.reduce(0, +),
                score: complete ? result.value : nil,
                scoreNote: complete ? result.note : "Analysis incomplete; score withheld.",
                measurementNote: measurementNote(metric)
            )
        }
        let scores = summaries.compactMap(\.score)
        let overall =
            complete && scores.count == Metric.allCases.count
            ? scores.reduce(0, +) / Double(scores.count) : nil
        diagnostics.sort { lhs, rhs in
            if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
            return lhs.message < rhs.message
        }
        return AnalysisReport(
            schemaVersion: 2, engineVersion: "0.1.0", typeScope: options.typeScope,
            scoringMode: options.scoring, complete: complete,
            inputFileCount: parsed.count, inputFiles: parsed.map(\.path).sorted(),
            minimumDuplicateLines: options.minimumDuplicateLines, analyzedFileCount: files.count,
            modules: Set(parsed.map(\.module)).sorted(), codeLineCount: codeLines,
            classScopeVariableCount: propertyCount,
            topLevelVariableCount: files.reduce(0) { $0 + $1.topLevelVariables },
            methodCount: methods.count, functionCount: functions.count,
            uniqueDuplicatedLineCount: duplication.uniqueLines,
            metrics: summaries, overallScore: overall,
            overallScoreNote: overall == nil
                ? "An overall score requires a complete analysis and all ten defined metric scores." : nil,
            findings: findings, diagnostics: diagnostics, couplings: edges, duplicateBlocks: duplication.blocks,
            debtItems: debtItems
        )
    }

    private func aggregate(
        _ fragments: [TypeFragment], scope: TypeScope, diagnostics: inout [AnalysisDiagnostic]
    ) -> [TypeKey: Aggregate] {
        var result: [TypeKey: Aggregate] = [:]
        for (key, group) in Dictionary(grouping: fragments, by: \.key) {
            let bases = group.filter { !$0.isExtension }
            guard let base = bases.first else { continue }
            guard scope == .nominals || base.kind == "class" else { continue }
            guard bases.count == 1 else {
                diagnostics.append(
                    AnalysisDiagnostic(
                        severity: .warning,
                        message:
                            "Ambiguous declarations for \(key.displayName); conditional compilation is not evaluated. Type metrics omitted.",
                        location: bases.sorted { locationOrder($0.location, $1.location) }[0].location
                    ))
                continue
            }
            result[key] = Aggregate(
                key: key, location: base.location, lines: group.reduce(0) { $0 + $1.codeLines },
                fields: group.reduce(into: Set<String>()) { $0.formUnion($1.propertyNames) }, fragments: group
            )
        }
        return result
    }

    private func couplingEdges(_ types: [TypeKey: Aggregate]) -> [CouplingEdge] {
        var edges: Set<CouplingEdge> = []
        for type in types.values {
            for fragment in type.fragments {
                for name in fragment.referencedTypes {
                    guard let other = resolve(name, from: type.key, imports: fragment.importedModules, types: types),
                        other != type.key
                    else { continue }
                    let endpoints = [type.key.displayName, other.displayName].sorted()
                    edges.insert(CouplingEdge(first: endpoints[0], second: endpoints[1]))
                }
            }
        }
        return edges.sorted { ($0.first, $0.second) < ($1.first, $1.second) }
    }

    private func resolve(
        _ name: String, from source: TypeKey, imports: Set<String>, types: [TypeKey: Aggregate]
    ) -> TypeKey? {
        var parents = source.name.split(separator: ".").map(String.init)
        while !parents.isEmpty {
            let candidate = TypeKey(module: source.module, name: (parents + [name]).joined(separator: "."))
            if types[candidate] != nil { return candidate }
            parents.removeLast()
        }
        let sameModule = TypeKey(module: source.module, name: name)
        if types[sameModule] != nil { return sameModule }
        let parts = name.split(separator: ".").map(String.init)
        if parts.count > 1 {
            let qualified = TypeKey(module: parts[0], name: parts.dropFirst().joined(separator: "."))
            if types[qualified] != nil { return qualified }
        }
        let imported = imports.map { TypeKey(module: $0, name: name) }.filter { types[$0] != nil }
        return imported.count == 1 ? imported[0] : nil
    }

    private func measurementNote(_ metric: Metric) -> String? {
        switch metric {
        case .nogc: "Class-scope property bindings (let/var, stored/computed), not true file-global variables."
        case .noav:
            "Conservative lexical field-use estimate; explicit self/Self and unshadowed bare names. No compiler binding resolution."
        case .nocc:
            "Undirected graph of resolved syntactic nominal references within selected inputs; not a compiler call graph."
        case .dc:
            "Native exact token-normalized line clones, not Lizard. Duplicated-line total is the union across all occurrences."
        case .ccf:
            "Documented decision-node policy; nested closures and local functions do not inflate enclosing functions."
        case .wmcc:
            "Sum of CCF over direct methods and accessor bodies; nested closures and local functions do not inflate enclosing functions."
        case .nomc: "Implemented func/init/deinit only; property and subscript accessors are not methods."
        default: nil
        }
    }
}

package func locationOrder(_ lhs: SourceLocation, _ rhs: SourceLocation) -> Bool {
    if lhs.file != rhs.file { return lhs.file < rhs.file }
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    return lhs.column < rhs.column
}
