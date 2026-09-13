import Foundation
import SCMACore
import Testing

@testable import SCMAKit
@testable import SCMAReporting

@Suite("Whole-source analysis and report boundaries")
struct AnalyzerTests {
    private func source(_ path: String, _ content: String, module: String = "App") -> SourceUnit {
        SourceUnit(path: path, module: module, content: content)
    }
    private func metric(_ id: Metric, in report: AnalysisReport) -> MetricSummary {
        report.metrics.first { $0.metric == id }!
    }

    @Test func allTenMetricsArePresent() async throws {
        let report = try await Analyzer().analyze([
            source("C.swift", "class C { var x = 0; func f(_ n: Int) { x = n } }")
        ])
        #expect(report.complete)
        #expect(report.schemaVersion == 2)
        #expect(report.metrics.map(\.metric) == Metric.allCases)
        #expect(metric(.noav, in: report).total == 1)
        #expect(report.overallScore == nil)
    }
    @Test func defaultIsClassesWithExplicitNominalExtension() async throws {
        let inputs = [source("Types.swift", "class C {}\nstruct S {}\nenum E {}\nactor A {}")]
        let classic = try await Analyzer().analyze(inputs)
        let extended = try await Analyzer().analyze(inputs, options: .init(typeScope: .nominals))
        #expect(metric(.locc, in: classic).observations.count == 1)
        #expect(metric(.locc, in: extended).observations.count == 4)
    }
    @Test func crossFileExtensionsMerge() async throws {
        let report = try await Analyzer().analyze([
            source("C.swift", "class C { var x = 0 }"),
            source("Extension.swift", "extension C { func f(_ n: Int) { self.x = n } }"),
        ])
        #expect(metric(.nomc, in: report).total == 1)
        #expect(metric(.noav, in: report).total == 1)
        #expect(metric(.locc, in: report).total == 2)
    }
    @Test func importedModuleCouplingIsSymmetric() async throws {
        let report = try await Analyzer().analyze([
            source("A.swift", "import Models\nclass A { var b: B? }", module: "App"),
            source("B.swift", "class B {}", module: "Models"),
        ])
        #expect(report.couplings.count == 1)
        #expect(metric(.nocc, in: report).observations.map(\.value) == [1, 1])
    }
    @Test func equalNamesInDifferentModulesAreNotMerged() async throws {
        let report = try await Analyzer().analyze([
            source("A.swift", "class C {}", module: "A"), source("B.swift", "class C {}", module: "B"),
        ])
        #expect(metric(.locc, in: report).observations.count == 2)
        #expect(report.complete)
    }
    @Test func ambiguousImportsDoNotInventCoupling() async throws {
        let report = try await Analyzer().analyze([
            source("A.swift", "import One\nimport Two\nclass A { var b: B? }"),
            source("One.swift", "class B {}", module: "One"), source("Two.swift", "class B {}", module: "Two"),
        ])
        #expect(report.couplings.isEmpty)
    }
    @Test func localShadowingDoesNotIncreaseFieldUsage() async throws {
        let report = try await Analyzer().analyze([
            source("A.swift", "class C { var x = 0; func f(x: Int) { other.x = x }; func g() { self.x = 2 } }")
        ])
        #expect(metric(.noav, in: report).observations.map(\.value) == [0, 1])
    }
    @Test func syntaxFailureSkipsFileByDefault() async throws {
        let report = try await Analyzer().analyze(
            [
                source("Good.swift", "class C { var x = 0; func f(_ n: Int) {} }"), source("Bad.swift", "class Bad {"),
            ], options: .init(scoring: .paper))
        #expect(report.complete)
        #expect(report.analyzedFileCount == 1)
        #expect(report.inputFileCount == 2)
        #expect(report.diagnostics.contains { $0.severity == .warning && $0.message.contains("File skipped") })
        #expect(metric(.locc, in: report).observations.count == 1)
        #expect(report.overallScore != nil)
    }
    @Test func strictSyntaxProducesIncompleteReportAndNoScore() async throws {
        let report = try await Analyzer().analyze(
            [
                source("Good.swift", "class C { var x = 0; func f(_ n: Int) {} }"), source("Bad.swift", "class Bad {"),
            ], options: .init(scoring: .paper, strictSyntax: true))
        #expect(!report.complete)
        #expect(report.analyzedFileCount == 1)
        #expect(report.overallScore == nil)
        #expect(report.metrics.allSatisfy { $0.score == nil })
    }
    @Test func conflictingConditionalDeclarationsWarnAndOmitTheType() async throws {
        let report = try await Analyzer().analyze([
            source(
                "C.swift", "#if os(iOS)\nclass C { func f() {} }\n#else\nclass C { func f() {} }\n#endif\nclass D {}")
        ])
        #expect(report.complete)
        #expect(report.diagnostics.contains { $0.severity == .warning && $0.message.contains("Ambiguous") })
        #expect(metric(.locc, in: report).observations.map(\.entity) == ["App.D"])
        #expect(metric(.locf, in: report).observations.count == 2)
    }
    @Test func nestedProtocolRequirementsAreNotClassProperties() async throws {
        let report = try await Analyzer().analyze([
            source("H.swift", "class H { var a = 0; protocol P { var b: Int { get }; func w() }; func f() { a = 1 } }")
        ])
        #expect(metric(.nogc, in: report).total == 1)
        #expect(metric(.nomc, in: report).total == 1)
    }
    @Test func accessorsCountForComplexityButNotAsMethods() async throws {
        let report = try await Analyzer().analyze([
            source(
                "A.swift",
                """
                class A {
                    var n = 0
                    var doubled: Int { if n > 0 { return n * 2 } else { return 0 } }
                    var stored: Int = 0 { didSet { if stored > n { n = stored } } }
                    subscript(i: Int) -> Int {
                        get { i > 0 && i < n ? i : 0 }
                        set { n = newValue }
                    }
                    func f() {}
                }
                """)
        ])
        #expect(metric(.nomc, in: report).total == 1)
        #expect(report.methodCount == 1)
        #expect(metric(.wmcc, in: report).total == 1 + 2 + 2 + 3 + 1)
        let names = metric(.ccf, in: report).observations.map(\.entity)
        #expect(names.contains("App.A.doubled.get()"))
        #expect(names.contains("App.A.stored.didSet()"))
        #expect(names.contains("App.A.subscript.get(i:)"))
        #expect(metric(.nopf, in: report).observations.first { $0.entity == "App.A.subscript.set(i:)" }?.value == 1)
        #expect(metric(.noav, in: report).observations.first { $0.entity == "App.A.stored.didSet()" }?.value == 2)
    }
    @Test func shadowingIsLexicallyScoped() async throws {
        let report = try await Analyzer().analyze([
            source(
                "S.swift",
                """
                class S {
                    var title = ""
                    var count = 0
                    func f(flag: Bool) {
                        if let title = Optional(title) { print(title) }
                        print(title)
                        guard let count = Optional(count) else { return }
                        print(count)
                    }
                    func g() { if true { let count = 1; print(count) }; print(count) }
                    func h() { let count = 1; print(count) }
                }
                """)
        ])
        #expect(metric(.noav, in: report).observations.map(\.value) == [2, 1, 0])
    }
    @Test func structuralDebtEvidenceCarriesLocationsAndExplanations() async throws {
        let repeated = (0..<3).map { "    let v\($0) = \($0)" }.joined(separator: "\n")
        let code = """
        class Worker {
            var values: [Int] = []
            func risky(flag: Bool) async throws {
                if flag {
                    for value in values {
                        if value > 0 {
                            print(value)
                        }
                    }
                }
            }
            func cloneA() {
        \(repeated)
            }
            func cloneB() {
        \(repeated)
            }
        }
        """
        let report = try await Analyzer().analyze(
            [source("Structural.swift", code)],
            options: .init(minimumDuplicateLines: 3)
        )
        let evidence = report.debtItems.flatMap(\.evidence)

        #expect(report.metrics.map(\.metric) == Metric.allCases)
        #expect(!evidence.isEmpty)
        #expect(evidence.allSatisfy { $0.location?.file != nil && $0.location?.line != nil })
        #expect(evidence.allSatisfy { $0.location?.column != nil })
        #expect(evidence.allSatisfy { !$0.rawValue.isEmpty })
        #expect(evidence.allSatisfy { $0.note?.isEmpty == false })
        #expect(evidence.contains { $0.kind == "swift.cognitive-complexity" && $0.rawValue == "value=6" })
        #expect(evidence.contains { $0.kind == "swift.nesting-depth" && $0.rawValue == "value=3" })
        #expect(evidence.contains { $0.kind == "swift.oversized-type" })
        #expect(evidence.contains { $0.kind == "swift.duplicate-lines" && $0.rawValue != "value=0" })
    }

    @Test func structuralDebtEvidenceIsDeterministicUnderParallelParsing() async throws {
        let body = (0..<4).map { "        let v\($0) = \($0)" }.joined(separator: "\n")
        let sources = (0..<12).map { index in
            source(
                "\(index).swift",
                """
                class C\(index) {
                    var value = \(index)
                    func f(_ flag: Bool) {
                        if flag {
                            for item in [value] {
                                if item > 0 { print(item) }
                            }
                        }
                \(body)
                    }
                }
                """
            )
        }
        let first = try await Analyzer().analyze(sources, options: .init(minimumDuplicateLines: 3), jobs: 1)
        let second = try await Analyzer().analyze(
            Array(sources.reversed()),
            options: .init(minimumDuplicateLines: 3),
            jobs: 4
        )

        #expect(first.debtItems == second.debtItems)
    }

    @Test func correctedScoringRepairsDuplicateRatioOnly() async throws {
        let block = (0..<12).map { "    let v\($0) = \($0)" }.joined(separator: "\n")
        let code = "class C {\n    func a(_ p: Int) {\n\(block)\n    }\n    func b() {\n\(block)\n    }\n}"
        let literal = try await Analyzer().analyze([source("C.swift", code)], options: .init(scoring: .paper))
        let corrected = try await Analyzer().analyze([source("C.swift", code)], options: .init(scoring: .corrected))
        #expect(metric(.dc, in: literal).score! < 0.1)
        let ratio = Double(corrected.uniqueDuplicatedLineCount) / Double(corrected.codeLineCount)
        #expect(metric(.dc, in: corrected).score == 2 / (ratio + 0.4))
        #expect(metric(.nogc, in: corrected).score == 5)
        #expect(metric(.nogc, in: literal).score! > 5)
    }
    @Test func customGatesDoNotRewritePaperRatios() async throws {
        let report = try await Analyzer().analyze(
            [source("C.swift", "class C { var x = 0; func f(_ n: Int) { if n > 0 {} } }")],
            options: .init(scoring: .paper, thresholds: [.ccf: 1]))
        #expect(metric(.ccf, in: report).violations == 1)
        #expect(metric(.ccf, in: report).paperViolations == 0)
        #expect(metric(.ccf, in: report).score == 5)
    }
    @Test func literalAverageUsesAllTenScores() async throws {
        let report = try await Analyzer().analyze(
            [source("C.swift", "class C { var x = 0; func f(_ n: Int) { x = n } }")], options: .init(scoring: .paper))
        let scores = report.metrics.compactMap(\.score)
        #expect(scores.count == 10)
        #expect(report.overallScore == scores.reduce(0, +) / 10)
    }
    @Test func zeroViolationsScoreFiveEvenWithZeroDenominator() async throws {
        let report = try await Analyzer().analyze(
            [source("C.swift", "class C { func f() {} }")], options: .init(scoring: .paper))
        #expect(metric(.nopf, in: report).score == 5)
        #expect(metric(.dc, in: report).score == 5)
        #expect(metric(.noav, in: report).score == nil)
        #expect(report.overallScore == nil)
    }
    @Test func configurationDecodeErrorsNameTheFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "class C {}".write(to: directory.appendingPathComponent("C.swift"), atomically: true, encoding: .utf8)
        try "{\"jobs\": \"many\"}".write(
            to: directory.appendingPathComponent(".scma.json"), atomically: true, encoding: .utf8)
        await #expect(throws: AnalysisFailure.self) {
            try await AnalysisService().run(.init(path: directory.path))
        }
        do {
            _ = try await AnalysisService().run(.init(path: directory.path))
        } catch {
            #expect("\(error)".contains(".scma.json"))
            #expect("\(error)".contains("jobs"))
        }
    }
    @Test func parallelismDoesNotChangeJSON() async throws {
        let sources = (0..<20).map { source("\($0).swift", "class C\($0) { func f(_ n: Int) { if n > 1 {} } }") }
        let first = try await Analyzer().analyze(sources, jobs: 1)
        let second = try await Analyzer().analyze(Array(sources.reversed()), jobs: 4)
        #expect(
            try ReportRenderer().render(first, format: .json, root: "/a")
                == ReportRenderer().render(second, format: .json, root: "/b"))
    }
    @Test func htmlEscapesUntrustedPathsAndCSVPreventsFormulaInjection() async throws {
        let report = try await Analyzer().analyze([
            source("=<script>alert(1)</script>.swift", "class C { func f() {} }")
        ])
        let html = try ReportRenderer().render(report, format: .html, root: "/root")
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;"))
        let csv = try ReportRenderer().render(report, format: .csv, root: "/root")
        #expect(csv.contains("\"'=<script>"))
    }
    @Test func emptyAndDuplicateInputPathsFail() async throws {
        await #expect(throws: AnalysisFailure.self) { try await Analyzer().analyze([]) }
        let value = source("same.swift", "class C {}")
        await #expect(throws: AnalysisFailure.self) { try await Analyzer().analyze([value, value]) }
    }
    @Test func unknownConfigurationKeysAndMetricsFail() throws {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(WorkspaceConfiguration.self, from: Data("{\"thresholdz\":{}}".utf8))
        }
        let config = try JSONDecoder().decode(
            WorkspaceConfiguration.self, from: Data("{\"thresholds\":{\"OTHER\":2}}".utf8))
        #expect(throws: AnalysisFailure.self) { try config.analysisOptions(overrides: .init()) }
    }
}
