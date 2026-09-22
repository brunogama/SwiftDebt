import Testing

@testable import SwiftDebtCore

@Suite("Coverage evidence boundary behavior")
struct CoverageEvidenceBoundaryTests {
    @Test("Missing sources, empty records, suffix paths, and line fallbacks stay explicit")
    func matchingFallbacksRemainAuditable() throws {
        let report = LcovReport(records: [
            LcovRecord(sourcePath: "Empty.swift"),
            LcovRecord(
                sourcePath: "workspace/Lines.swift",
                lineHits: [
                    LcovLineHit(line: 10, hits: 0),
                    LcovLineHit(line: 11, hits: 2),
                    LcovLineHit(line: 12, hits: 3),
                ]
            ),
            LcovRecord(
                sourcePath: "Suffix.swift",
                functionHits: [LcovFunctionHit(name: "run()", hits: 0)]
            ),
            LcovRecord(sourcePath: "/repo", lineHits: [LcovLineHit(line: 1, hits: 1)]),
        ])
        let entities = [
            coverageEntity("same", "Zed", level: .callable),
            coverageEntity("same", "Alpha", level: .file, file: "Empty.swift", line: 1),
            coverageEntity("aggregate", "Lines", level: .module, file: "Lines.swift", line: 1),
            coverageEntity("line-zero", "missingZero()", level: .callable, file: "Lines.swift", line: 10),
            coverageEntity("line-hit", "missingHit()", level: .callable, file: "Lines.swift", line: 11),
            coverageEntity("suffix", "App.run()", level: .callable, file: "Suffix.swift", line: 1),
            coverageEntity("root", "Repository root", level: .file, file: "", line: 1),
        ]

        let result = CoverageMatcher().match(report: report, entities: entities, repositoryRoot: "/repo")

        #expect(result.diagnostics.first { $0.entityDisplayName == "Zed" }?.availability == .missingFile)
        #expect(result.diagnostics.first { $0.entityDisplayName == "Alpha" }?.availability == .unmatchedEntity)
        #expect(result.diagnostics.first { $0.entityID == "aggregate" }?.confidence == .high)
        #expect(result.evidence.first { $0.id == "aggregate:coverage:lcov" }?.rawValue.contains("66.7%") == true)
        #expect(result.diagnostics.first { $0.entityID == "line-zero" }?.availability == .zeroCoverage)
        #expect(result.diagnostics.first { $0.entityID == "line-hit" }?.availability == .measuredCoverage)
        #expect(result.diagnostics.first { $0.entityID == "line-hit" }?.confidence == .fallback)
        #expect(result.diagnostics.first { $0.entityID == "suffix" }?.confidence == .high)
        #expect(result.diagnostics.first { $0.entityID == "root" }?.availability == .measuredCoverage)
        #expect(result.evidence.map(\.id) == result.evidence.map(\.id).sorted())
    }

    @Test("Diagnostic rendering is deterministic for absent optional subjects")
    func diagnosticRenderingHandlesAbsentSubjects() {
        let diagnostics = [
            CoverageDiagnostic(
                entityID: "same",
                entityDisplayName: nil,
                sourcePath: "B.swift",
                matchedSourcePath: nil,
                matchedFunction: nil,
                availability: .unmatchedEntity,
                confidence: .unmatched,
                attemptedStrategies: [],
                message: "z-message"
            ),
            CoverageDiagnostic(
                entityID: "same",
                entityDisplayName: nil,
                sourcePath: "A.swift",
                matchedSourcePath: nil,
                matchedFunction: nil,
                availability: .missingFile,
                confidence: .unmatched,
                attemptedStrategies: [.sourcePathExact],
                message: "b-message"
            ),
            CoverageDiagnostic(
                entityID: "same",
                entityDisplayName: nil,
                sourcePath: "A.swift",
                matchedSourcePath: nil,
                matchedFunction: nil,
                availability: .missingFile,
                confidence: .unmatched,
                attemptedStrategies: [.sourcePathSuffix],
                message: "a-message"
            ),
            CoverageDiagnostic(
                entityID: "same",
                entityDisplayName: nil,
                sourcePath: nil,
                matchedSourcePath: nil,
                matchedFunction: nil,
                availability: .missingFile,
                confidence: .unmatched,
                attemptedStrategies: [],
                message: "missing-source"
            ),
            CoverageDiagnostic(
                entityID: nil,
                entityDisplayName: nil,
                sourcePath: nil,
                matchedSourcePath: nil,
                matchedFunction: nil,
                availability: .unmatchedEntity,
                confidence: .unmatched,
                attemptedStrategies: [],
                message: "unknown"
            ),
            CoverageDiagnostic(
                entityID: "nil-source",
                entityDisplayName: "Nil source A",
                sourcePath: nil,
                matchedSourcePath: nil,
                matchedFunction: nil,
                availability: .missingFile,
                confidence: .unmatched,
                attemptedStrategies: [],
                message: "nil-source-a"
            ),
            CoverageDiagnostic(
                entityID: "nil-source",
                entityDisplayName: "Nil source B",
                sourcePath: nil,
                matchedSourcePath: nil,
                matchedFunction: nil,
                availability: .missingFile,
                confidence: .unmatched,
                attemptedStrategies: [],
                message: "nil-source-b"
            ),
        ]

        let output = CoverageMatcher().renderDiagnostics(diagnostics)
        let reversedOutput = CoverageMatcher().renderDiagnostics(Array(diagnostics.reversed()))

        #expect(output == reversedOutput)
        #expect(output.contains("coverage: <unknown>"))
        #expect(output.contains("source=<none>"))
        #expect(output.firstRange(of: "a-message")!.lowerBound < output.firstRange(of: "b-message")!.lowerBound)
        #expect(CoverageMatcher().renderDiagnostics([]).isEmpty)
    }

    @Test("Path normalization treats separators and parent components consistently")
    func pathNormalizationIsCrossPlatform() {
        #expect(normalizedPath(#"C:\repo\Sources\..\App.swift"#) == "C:/repo/App.swift")
        #expect(normalizedPath("/repo/./Sources/../App.swift") == "/repo/App.swift")
        #expect(normalizedPath("../../App.swift") == "App.swift")
    }
}

@Suite("LCOV parser boundary behavior")
struct LcovParserBoundaryTests {
    @Test("Duplicate coordinates are sorted deterministically and malformed entries are ignored")
    func duplicateCoordinatesHaveStableOrder() {
        let report = LcovParser().parse(
            """
            SF:Z.swift  \r
            FN:2,zeta
            FN:2,alpha
            FN:not-a-line,ignored
            FNDA:3,same
            FNDA:1,same
            FNDA:not-hits,ignored
            DA:4,2
            DA:4,1
            DA:broken
            end_of_record
            SF:A.swift
            end_of_record
            """
        )

        #expect(report.records.map(\.sourcePath) == ["A.swift", "Z.swift"])
        let record = report.records[1]
        #expect(
            record.functions == [
                LcovFunctionDefinition(line: 2, name: "alpha"),
                LcovFunctionDefinition(line: 2, name: "zeta"),
            ])
        #expect(
            record.functionHits == [
                LcovFunctionHit(name: "same", hits: 1),
                LcovFunctionHit(name: "same", hits: 3),
            ])
        #expect(
            record.lineHits == [
                LcovLineHit(line: 4, hits: 1),
                LcovLineHit(line: 4, hits: 2),
            ])
    }
}

@Suite("Functional debt evidence boundary behavior")
struct FunctionalDebtEvidenceBoundaryTests {
    @Test("Every effect and Swift risk category produces deterministic evidence")
    func allEffectAndRiskCategoriesRemainAuditable() throws {
        let location = SourceLocation(file: "Effects.swift", line: 10, column: 2)
        var effects = SyntaxEffectCategory.allCases.enumerated().map { index, category in
            SyntaxEffectFact(
                category: category,
                detail: "\(category.rawValue)-\(index)",
                location: location,
                confidence: .measuredSyntax,
                inClosure: false
            )
        }
        effects += [
            SyntaxEffectFact(
                category: .mutation,
                detail: "ordered",
                location: SourceLocation(file: "Effects.swift", line: 9),
                confidence: .heuristic,
                inClosure: true
            ),
            SyntaxEffectFact(
                category: .mutation,
                detail: "ordered",
                location: location,
                confidence: .measuredSyntax,
                inClosure: false
            ),
            SyntaxEffectFact(
                category: .mutation,
                detail: "ordered",
                location: location,
                confidence: .heuristic,
                inClosure: false
            ),
            SyntaxEffectFact(
                category: .mutation,
                detail: "ordered",
                location: location,
                confidence: .heuristic,
                inClosure: true
            ),
        ]
        let compositions = [
            FunctionalCompositionFact(
                operation: "zipped",
                location: SourceLocation(file: "Effects.swift", line: 8),
                closureHasSideEffects: false,
                confidence: .heuristic
            ),
            FunctionalCompositionFact(
                operation: "map",
                location: location,
                closureHasSideEffects: false,
                confidence: .measuredSyntax
            ),
            FunctionalCompositionFact(
                operation: "map",
                location: location,
                closureHasSideEffects: true,
                confidence: .measuredSyntax
            ),
            FunctionalCompositionFact(
                operation: "map",
                location: location,
                closureHasSideEffects: true,
                confidence: .heuristic
            ),
            FunctionalCompositionFact(
                operation: "reduce",
                location: location,
                closureHasSideEffects: false,
                confidence: .measuredSyntax
            ),
        ]
        var risks = SwiftRiskCategory.allCases.enumerated().map { index, category in
            SwiftRiskFact(
                category: category,
                detail: "\(category.rawValue)-\(index)",
                location: location,
                confidence: .heuristic
            )
        }
        risks += [
            SwiftRiskFact(
                category: .isolationCrossing,
                detail: "ordered",
                location: SourceLocation(file: "Effects.swift", line: 9),
                confidence: .measuredSyntax
            ),
            SwiftRiskFact(
                category: .isolationCrossing,
                detail: "ordered-a",
                location: location,
                confidence: .heuristic
            ),
            SwiftRiskFact(
                category: .isolationCrossing,
                detail: "ordered-b",
                location: location,
                confidence: .measuredSyntax
            ),
            SwiftRiskFact(
                category: .isolationCrossing,
                detail: "ordered-b",
                location: location,
                confidence: .heuristic
            ),
        ]
        let functions = [
            makeFunction(
                name: "App.zeta()",
                location: location,
                codeLines: 24,
                complexity: 6,
                parameters: 8,
                accessLevel: "public",
                effectFacts: effects,
                compositionFacts: compositions,
                riskFacts: risks
            ),
            makeFunction(name: "App.alpha()", location: location),
        ]
        let valid = makeSource(
            path: "Effects.swift",
            functions: functions,
            riskFacts: [
                SwiftRiskFact(
                    category: .mutableSharedState,
                    detail: "global cache",
                    location: SourceLocation(file: "Effects.swift", line: 1)
                )
            ]
        )
        let invalid = makeSource(
            path: "Invalid.swift",
            diagnostics: [
                AnalysisDiagnostic(
                    severity: .error,
                    message: "invalid fixture",
                    location: SourceLocation(file: "Invalid.swift", line: 1)
                )
            ]
        )

        let evidence = DebtFunctionalEvidenceBuilder().evidence(for: [invalid, valid])
        let shuffled = DebtFunctionalEvidenceBuilder().evidence(
            for: [
                invalid,
                makeSource(path: "Effects.swift", functions: Array(functions.reversed()), riskFacts: valid.riskFacts),
            ]
        )

        #expect(evidence == shuffled)
        #expect(evidence.contains { $0.kind == "swift.shared-state.mutable" })
        #expect(evidence.contains { $0.kind == "swift.side-effect.inoutMutation" })
        #expect(evidence.contains { $0.kind == "swift.side-effect.throwingEffect" })
        #expect(evidence.contains { $0.kind == "swift.concurrency-risk.sendableConformance" })
        #expect(evidence.contains { $0.kind == "swift.concurrency-risk.uncheckedSendable" })
        #expect(evidence.contains { $0.kind == "swift.concurrency-risk.nonisolatedDeclaration" })
        #expect(evidence.contains { $0.kind == "swift.concurrency-risk.unsafeEscapeHatch" })
        #expect(evidence.contains { $0.kind == "swift.api-risk.parameter-surface" })
        #expect(evidence.contains { $0.kind == "swift.api-risk.public-boundary-complexity" })
        let composition = try #require(evidence.first { $0.kind == "swift.functional-composition" })
        #expect(composition.rawValue.contains("operations=zipped,map,map,map,reduce"))
        #expect(composition.rawValue.contains("impureClosures=2"))
        #expect(!evidence.contains { $0.location?.file == "Invalid.swift" })
    }
}

@Suite("Dependency graph resolution boundaries")
struct DependencyGraphBoundaryTests {
    @Test("Nested, qualified, imported, ambiguous, and unresolved references remain distinct")
    func graphResolutionIsExplicitAndDeterministic() throws {
        let outer = TypeKey(module: "App", name: "Outer")
        let worker = TypeKey(module: "App", name: "Worker")
        let sharedLocation = SourceLocation(file: "Sources/App/Calls.swift", line: 20)
        let callSites = [
            CallSiteFact(name: "self.run", labels: "", location: sharedLocation),
            CallSiteFact(name: "Self.run", labels: "", location: sharedLocation),
            CallSiteFact(name: "Tools.help", labels: "", location: sharedLocation),
            CallSiteFact(name: "bare", labels: "", location: sharedLocation),
            CallSiteFact(name: "bare", labels: "_:", location: sharedLocation),
            CallSiteFact(name: "overload", labels: "_:", location: sharedLocation),
            CallSiteFact(name: "unknown", labels: "", location: sharedLocation),
            CallSiteFact(name: "", labels: "", location: sharedLocation),
        ]
        let sources = [
            makeSource(
                path: "Sources/App/Outer.swift",
                types: [
                    makeFragment(
                        key: outer,
                        file: "Sources/App/Outer.swift",
                        referencedTypes: [
                            "Inner", "Models.Qualified", "External", "Shared", "Orphan", "Unknown", "Outer",
                        ],
                        importedModules: ["Models", "One", "Two"]
                    ),
                    makeFragment(
                        key: outer,
                        isExtension: true,
                        file: "Sources/App/MissingExtension.swift"
                    ),
                    makeFragment(key: TypeKey(module: "App", name: "Outer.Inner"), file: "Sources/App/Outer.swift"),
                    makeFragment(key: TypeKey(module: "App", name: #"Odd"\Name"#), file: "Sources/App/Outer.swift"),
                ]
            ),
            makeSource(
                path: "Sources/Models/Models.swift",
                module: "Models",
                types: [
                    makeFragment(key: TypeKey(module: "Models", name: "External"), file: "Sources/Models/Models.swift"),
                    makeFragment(
                        key: TypeKey(module: "Models", name: "Qualified"), file: "Sources/Models/Models.swift"),
                ]
            ),
            makeSource(
                path: "Sources/One/Shared.swift",
                module: "One",
                types: [makeFragment(key: TypeKey(module: "One", name: "Shared"), file: "Sources/One/Shared.swift")]
            ),
            makeSource(
                path: "Sources/Two/Shared.swift",
                module: "Two",
                types: [makeFragment(key: TypeKey(module: "Two", name: "Shared"), file: "Sources/Two/Shared.swift")]
            ),
            makeSource(
                path: "Sources/A/Orphan.swift",
                module: "A",
                types: [makeFragment(key: TypeKey(module: "A", name: "Orphan"), file: "Sources/A/Orphan.swift")]
            ),
            makeSource(
                path: "Sources/B/Orphan.swift",
                module: "B",
                types: [makeFragment(key: TypeKey(module: "B", name: "Orphan"), file: "Sources/B/Orphan.swift")]
            ),
            makeSource(
                path: "Sources/App/Calls.swift",
                functions: [
                    makeFunction(
                        name: "App.Worker.source()",
                        owner: worker,
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 1),
                        callSites: callSites
                    ),
                    makeFunction(
                        name: "App.globalCaller()",
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 2),
                        callSites: [CallSiteFact(name: "global", labels: "", location: sharedLocation)]
                    ),
                    makeFunction(
                        name: "App.Worker.run()",
                        owner: worker,
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 3)
                    ),
                    makeFunction(
                        name: "App.Tools.help()",
                        owner: worker,
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 4)
                    ),
                    makeFunction(
                        name: "App.Worker.bare()",
                        owner: worker,
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 5)
                    ),
                    makeFunction(
                        name: "App.global()",
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 6)
                    ),
                    makeFunction(
                        name: "App.Worker.overload(_:)",
                        owner: worker,
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 7)
                    ),
                    makeFunction(
                        name: "App.Worker.overload(_:)",
                        owner: worker,
                        location: SourceLocation(file: "Sources/App/Calls.swift", line: 8)
                    ),
                ]
            ),
        ]

        let graph = DependencyGraphBuilder().build(from: sources, typeScope: .nominals)
        let shuffled = DependencyGraphBuilder().build(from: Array(sources.reversed()), typeScope: .nominals)

        #expect(graph == shuffled)
        #expect(
            graph.edges.contains { edge in
                edge.kind == .typeReference && edge.target == "type:App.Outer.Inner"
            })
        #expect(
            graph.edges.contains { edge in
                edge.kind == .typeReference && edge.target == "type:Models.Qualified"
            })
        #expect(
            graph.edges.contains { edge in
                edge.kind == .typeReference && edge.target == "type:Models.External"
            })
        let shared = try #require(graph.edges.first { $0.unresolvedName == "Shared" })
        #expect(shared.confidence == .ambiguousSyntax)
        #expect(shared.targetCandidates == ["type:One.Shared", "type:Two.Shared"])
        let orphan = try #require(graph.edges.first { $0.unresolvedName == "Orphan" })
        #expect(orphan.confidence == .ambiguousSyntax)
        #expect(orphan.targetCandidates == ["type:A.Orphan", "type:B.Orphan"])
        #expect(graph.edges.contains { $0.unresolvedName == "Unknown" && $0.confidence == .unresolvedSyntax })
        #expect(graph.edges.filter { $0.target?.contains("App.Worker.run()") == true }.count == 2)
        #expect(graph.edges.contains { $0.unresolvedName == "overload(_:)" && $0.confidence == .ambiguousSyntax })
        #expect(graph.edges.contains { $0.unresolvedName == "()" && $0.confidence == .unresolvedSyntax })
        #expect(graph.edges.contains { $0.kind == .moduleDependency && $0.target == "module:Models" })
        #expect(graph.dot.contains(#"Odd\"\\Name"#))
    }
}

@Suite("Ranked debt analysis boundaries")
struct RankedDebtAnalysisBoundaryTests {
    @Test("Unscored items sort after scores and every filter rejects ineligible items")
    func rankingAndFiltersPreserveUnknownRisk() throws {
        let items = [
            makeDebtItem(id: "empty", level: .callable, file: "A.swift", evidence: []),
            makeDebtItem(id: "low", level: .type, file: "A.swift", score: 20, kind: "swift.low"),
            makeDebtItem(id: "high", level: .file, file: "B.swift", score: 90, kind: "swift.high"),
            makeDebtItem(
                id: "coverage",
                level: .callable,
                file: "B.swift",
                evidence: [
                    DebtEvidence(id: "base", kind: "swift.metric", weight: 1, normalizedScore: 70, rawValue: "base"),
                    DebtEvidence(
                        id: "coverage", kind: "coverage.lcov", weight: 1, normalizedScore: 50, rawValue: "covered=1/2"),
                ]
            ),
            makeDebtItem(
                id: "unavailable",
                level: .module,
                file: nil,
                evidence: [
                    DebtEvidence(
                        id: "required",
                        kind: "git-history.churn",
                        requirement: .required,
                        availability: .unavailable(reason: "provider unavailable"),
                        weight: 1,
                        normalizedScore: nil,
                        rawValue: "missing"
                    )
                ]
            ),
            makeDebtItem(id: "empty-kind", level: .callable, file: "A.swift", score: 60, kind: ""),
        ]
        let ranked = DebtAnalysisBuilder(
            options: DebtAnalysisOptions(aggregationStrategy: .none)
        ).analyze(items: items)

        #expect(ranked.items.first?.item.id == "high")
        #expect(ranked.items.suffix(2).map(\.item.id).contains("empty"))
        #expect(
            ranked.items.first { $0.item.id == "empty" }?.explanation == "No evidence was available for this debt item."
        )
        #expect(ranked.items.first { $0.item.id == "empty-kind" }?.category == "")
        #expect(ranked.items.first { $0.item.id == "coverage" }?.recommendation.contains("Prioritize tests") == true)
        #expect(
            ranked.items.first { $0.item.id == "unavailable" }?.recommendation.contains("unavailable evidence") == true)

        let scoreFiltered = DebtAnalysisBuilder(
            options: DebtAnalysisOptions(aggregationStrategy: .none, minScore: 50)
        ).analyze(items: items)
        #expect(scoreFiltered.items.map(\.item.id) == ["high", "empty-kind"])

        let priorityFiltered = DebtAnalysisBuilder(
            options: DebtAnalysisOptions(aggregationStrategy: .none, minPriority: .critical)
        ).analyze(items: items)
        #expect(priorityFiltered.items.map(\.item.id) == ["high"])

        let levelFiltered = DebtAnalysisBuilder(
            options: DebtAnalysisOptions(aggregationStrategy: .none, levels: [.type])
        ).analyze(items: items)
        #expect(levelFiltered.items.map(\.item.id) == ["low"])

        let categoryFiltered = DebtAnalysisBuilder(
            options: DebtAnalysisOptions(aggregationStrategy: .none, categories: ["history"])
        ).analyze(items: items)
        #expect(categoryFiltered.items.isEmpty)
    }

    @Test("File aggregation ignores missing file keys and orders equal identifiers deterministically")
    func aggregationRequiresAFileIdentity() throws {
        let items = [
            makeDebtItem(
                id: "b",
                level: .callable,
                file: "A.swift",
                evidence: [DebtEvidence(id: "same", kind: "z", weight: 1, normalizedScore: 80, rawValue: "b")]
            ),
            makeDebtItem(
                id: "a",
                level: .callable,
                file: "A.swift",
                evidence: [DebtEvidence(id: "same", kind: "a", weight: 1, normalizedScore: 80, rawValue: "a")]
            ),
            makeDebtItem(id: "no-file", level: .module, file: nil, score: 100, kind: "swift.module"),
        ]

        let analysis = DebtAnalysisBuilder(
            options: DebtAnalysisOptions(aggregationStrategy: .file, problematicItemScoreThreshold: 0)
        ).analyze(items: items)

        let aggregation = try #require(analysis.aggregations.first)
        #expect(analysis.aggregations.count == 1)
        #expect(aggregation.id == "file:A.swift")
        #expect(aggregation.memberItemIDs == ["a", "b"])
    }
}

@Suite("Structural debt and metric boundaries")
struct StructuralDebtAndMetricsBoundaryTests {
    @Test("Empty files and invalid duplicate ranges use stable structural anchors")
    func emptyFilesAndInvalidDuplicateRangesRemainSafe() throws {
        let location = SourceLocation(file: "Empty.swift", line: 7)
        let functions = [
            makeFunction(name: "App.zeta()", location: location),
            makeFunction(name: "App.alpha()", location: location),
        ]
        let type = StructuralTypeFacts(
            key: TypeKey(module: "App", name: "Empty"),
            location: location,
            codeLines: 0,
            propertyCount: 0,
            methodCount: 0,
            weightedMethodComplexity: 0,
            callableNames: []
        )
        let invalidOccurrence = DuplicateOccurrence(file: "Empty.swift", startLine: 5, endLine: 3, codeLines: 0)
        let block = DuplicateBlock(first: invalidOccurrence, second: invalidOccurrence)
        let items = StructuralDebtBuilder().items(
            files: [makeSource(path: "Empty.swift", functions: functions, lines: [])],
            types: [type],
            functions: functions,
            duplicateBlocks: [block]
        )

        #expect(items.first { $0.id == "file:Empty.swift" }?.entity.location.line == 1)
        #expect(items.first { $0.id == "module:App" }?.entity.location.line == 1)
        #expect(
            items.filter { $0.entity.level == .callable }.map(\.id) == [
                "callable:App.alpha()", "callable:App.zeta()",
            ])
        #expect(
            items.first { $0.id == "file:Empty.swift" }?.evidence.first { $0.kind == "swift.duplicate-lines" }?.rawValue
                == "value=0")
        #expect(StructuralDebtBuilder().normalized(1, threshold: 0) == 100)
        #expect(StructuralDebtBuilder().normalized(0, threshold: 0) == 0)
    }

    @Test("Metric analysis rejects no input and downgrades skipped-file parse errors deterministically")
    func metricInputAndDiagnosticBoundariesAreExplicit() throws {
        #expect(throws: AnalysisFailure.self) {
            try MetricsCalculator().analyze([], options: AnalysisOptions())
        }
        let diagnosticLocation = SourceLocation(file: "Broken.swift", line: 1)
        let invalid = makeSource(
            path: "Broken.swift",
            diagnostics: [
                AnalysisDiagnostic(severity: .warning, message: "z-warning", location: diagnosticLocation),
                AnalysisDiagnostic(severity: .error, message: "b-error", location: diagnosticLocation),
                AnalysisDiagnostic(severity: .warning, message: "a-warning", location: diagnosticLocation),
            ]
        )
        let outer = TypeKey(module: "App", name: "Outer")
        let valid = makeSource(
            path: "Types.swift",
            types: [
                makeFragment(
                    key: outer,
                    file: "Types.swift",
                    referencedTypes: ["Inner", "Models.Thing"]
                ),
                makeFragment(key: TypeKey(module: "App", name: "Outer.Inner"), file: "Types.swift"),
                makeFragment(
                    key: TypeKey(module: "App", name: "ExtensionOnly"), isExtension: true, file: "Types.swift"),
                makeFragment(key: TypeKey(module: "Models", name: "Thing"), file: "Types.swift"),
            ]
        )

        let report = try MetricsCalculator().analyze([invalid, valid], options: AnalysisOptions(typeScope: .nominals))

        #expect(report.complete)
        #expect(report.diagnostics.map(\.severity) == [.warning, .warning, .warning])
        #expect(
            report.diagnostics.map(\.message) == [
                "File skipped (parse error): b-error", "a-warning", "z-warning",
            ])
        #expect(report.couplings.contains { $0.first == "App.Outer" && $0.second == "App.Outer.Inner" })
        #expect(report.couplings.contains { $0.first == "App.Outer" && $0.second == "Models.Thing" })
    }
}

private func coverageEntity(
    _ id: String,
    _ displayName: String,
    level: DebtAggregationLevel,
    file: String? = nil,
    line: Int? = nil
) -> DebtEntity {
    DebtEntity(
        id: id,
        displayName: displayName,
        level: level,
        location: DebtLocation(module: "App", file: file, line: line)
    )
}

private func makeFunction(
    name: String,
    owner: TypeKey? = nil,
    location: SwiftDebtCore.SourceLocation,
    kind: CallableKind = .method,
    codeLines: Int = 1,
    complexity: Int = 1,
    cognitiveComplexity: Int = 0,
    maxNestingDepth: Int = 0,
    parameters: Int = 0,
    accessLevel: String? = nil,
    effectFacts: [SyntaxEffectFact] = [],
    compositionFacts: [FunctionalCompositionFact] = [],
    callSites: [CallSiteFact] = [],
    riskFacts: [SwiftRiskFact] = []
) -> FunctionFacts {
    FunctionFacts(
        name: name,
        kind: kind,
        owner: owner,
        location: location,
        codeLines: codeLines,
        complexity: complexity,
        cognitiveComplexity: cognitiveComplexity,
        maxNestingDepth: maxNestingDepth,
        parameters: parameters,
        bareReferences: [],
        explicitSelfReferences: [],
        shadowedNames: [],
        accessLevel: accessLevel,
        effectFacts: effectFacts,
        compositionFacts: compositionFacts,
        callSites: callSites,
        riskFacts: riskFacts
    )
}

private func makeSource(
    path: String,
    module: String = "App",
    types: [TypeFragment] = [],
    functions: [FunctionFacts] = [],
    lines: [String] = ["code"],
    diagnostics: [AnalysisDiagnostic] = [],
    riskFacts: [SwiftRiskFact] = []
) -> ParsedSource {
    ParsedSource(
        path: path,
        module: module,
        types: types,
        functions: functions,
        lines: lines.enumerated().map { CodeLine(number: $0.offset + 1, signature: $0.element) },
        topLevelVariables: 0,
        diagnostics: diagnostics,
        riskFacts: riskFacts
    )
}

private func makeFragment(
    key: TypeKey,
    kind: String = "class",
    isExtension: Bool = false,
    file: String,
    referencedTypes: Set<String> = [],
    importedModules: Set<String> = []
) -> TypeFragment {
    TypeFragment(
        key: key,
        kind: kind,
        isExtension: isExtension,
        location: SourceLocation(file: file, line: 1),
        codeLines: 1,
        propertyNames: [],
        referencedTypes: referencedTypes,
        importedModules: importedModules
    )
}

private func makeDebtItem(
    id: String,
    level: DebtAggregationLevel,
    file: String?,
    score: Double? = nil,
    kind: String = "swift.metric",
    evidence: [DebtEvidence]? = nil
) -> DebtItem {
    let entity = DebtEntity(
        id: id,
        displayName: id,
        level: level,
        location: DebtLocation(module: "App", file: file, line: file == nil ? nil : 1)
    )
    let resolvedEvidence =
        evidence ?? score.map { value in
            [
                DebtEvidence(
                    id: "\(id):evidence", kind: kind, weight: 1, normalizedScore: value, rawValue: "value=\(value)")
            ]
        } ?? []
    return DebtItem(id: id, entity: entity, evidence: resolvedEvidence)
}
