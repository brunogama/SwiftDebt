import Testing

@testable import SCMACore

@Suite("Paper equations and native clone engine")
struct CoreTests {
    private let inputs = ScoreInputs(
        methodCount: 4, propertyCount: 2, parameterCount: 8, duplicateLines: 12, totalLines: 100)

    @Test(arguments: [Metric.locc, .nomc, .nogc, .nocc, .locf])
    func literalEquations(metric: Metric) {
        let result = PaperScoring().score(metric: metric, values: [10, 20], inputs: inputs, mode: .paper)
        let expected: Double
        switch metric {
        case .locc: expected = 1000.0 / 1520
        case .nomc, .nogc: expected = 500.0 / 95
        case .nocc: expected = 1000.0 / 170
        default: expected = 2000.0 / 320
        }
        #expect(result.value == expected)
    }

    @Test func originalRatioThresholds() {
        let result = PaperScoring().score(metric: .ccf, values: [20, 21], inputs: inputs, mode: .paper)
        #expect(result.value == 2 / (21.0 / 41 + 0.4))
    }
    @Test func noViolationIsFiveForPositiveDenominator() {
        #expect(PaperScoring().score(metric: .nopf, values: [1, 10], inputs: inputs, mode: .paper).value == 5)
    }
    @Test func inconsistentPaperRangeIsPreserved() {
        #expect(PaperScoring().score(metric: .nomc, values: [0], inputs: inputs, mode: .paper).value! > 5)
        #expect(PaperScoring().score(metric: .nomc, values: [0], inputs: inputs, mode: .bounded).value == 5)
        #expect(PaperScoring().score(metric: .locc, values: [0], inputs: inputs, mode: .paper).value! < 1)
    }
    @Test func literalNOAVAndDuplicateEquations() {
        #expect(PaperScoring().score(metric: .noav, values: [2], inputs: inputs, mode: .paper).value == 2 / 2.4)
        #expect(PaperScoring().score(metric: .dc, values: [12], inputs: inputs, mode: .paper).value == 2 / 150.4)
    }
    @Test(arguments: [Metric.wmcc, .ccf, .nopf, .dc])
    func zeroViolationsAreFiveRegardlessOfDenominator(metric: Metric) {
        let zero = ScoreInputs(methodCount: 0, propertyCount: 0, parameterCount: 0, duplicateLines: 0, totalLines: 0)
        #expect(PaperScoring().score(metric: metric, values: [0], inputs: zero, mode: .paper).value == 5)
    }
    @Test func undefinedIsNotPassing() {
        let zero = ScoreInputs(methodCount: 0, propertyCount: 0, parameterCount: 0, duplicateLines: 3, totalLines: 0)
        #expect(PaperScoring().score(metric: .noav, values: [0], inputs: zero, mode: .paper).value == nil)
        #expect(PaperScoring().score(metric: .dc, values: [3], inputs: zero, mode: .paper).value == nil)
        #expect(PaperScoring().score(metric: .dc, values: [3], inputs: zero, mode: .corrected).value == nil)
    }
    @Test func correctedModeOnlyChangesDuplicateRatio() {
        let corrected = PaperScoring().score(metric: .dc, values: [12], inputs: inputs, mode: .corrected)
        #expect(corrected.value == 2 / (12.0 / 100 + 0.4))
        #expect(corrected.note?.contains("repair") == true)
        #expect(PaperScoring().score(metric: .nomc, values: [0], inputs: inputs, mode: .corrected).value == 5)
        let locc = PaperScoring().score(metric: .locc, values: [0], inputs: inputs, mode: .corrected)
        #expect(locc.value == 1000.0 / 1500)
    }
    @Test func absentMetricsDoNotGetPerfectScores() {
        #expect(PaperScoring().score(metric: .nomc, values: [], inputs: inputs, mode: .paper).value == nil)
        #expect(PaperScoring().score(metric: .nomc, values: [1], inputs: inputs, mode: .none).value == nil)
    }
    @Test func configurationRejectsInvalidLimits() throws {
        #expect(throws: AnalysisFailure.self) { try AnalysisOptions(minimumDuplicateLines: 1).validate() }
        #expect(throws: AnalysisFailure.self) { try AnalysisOptions(thresholds: [.ccf: -1]).validate() }
    }

    @Test func exactCrossFileClonesAndUnion() throws {
        let files = [file("A.swift", ["a", "b", "c", "d"]), file("B.swift", ["a", "b", "c", "d"])]
        let result = try DuplicateDetector().detect(files, options: AnalysisOptions(minimumDuplicateLines: 2))
        #expect(result.blocks.count == 1)
        #expect(result.blocks.first?.first.codeLines == 4)
        #expect(result.uniqueLines == 8)
    }
    @Test func rejectsNearClonesAndOverlappingSelfMatches() throws {
        let options = AnalysisOptions(minimumDuplicateLines: 3)
        let result = try DuplicateDetector().detect(
            [file("A", ["a", "a", "a", "a"]), file("B", ["x", "b", "c"])], options: options)
        #expect(result.blocks.isEmpty)
        #expect(result.uniqueLines == 0)
        // A valid, oversized floor must not loop through an enormous hash exponent.
        let oversized = AnalysisOptions(thresholds: [.dc: Int.max], minimumDuplicateLines: Int.max)
        try oversized.validate()
        let tooShort = try DuplicateDetector().detect([file("small", ["a", "b"])], options: oversized)
        #expect(tooShort.blocks.isEmpty)
    }
    @Test func sameFileNonoverlappingClone() throws {
        let result = try DuplicateDetector().detect(
            [file("A", ["a", "b", "c", "x", "a", "b", "c"])], options: AnalysisOptions(minimumDuplicateLines: 3))
        #expect(result.blocks.count == 1)
        #expect(result.uniqueLines == 6)
    }
    @Test func budgetFailsExplicitly() throws {
        #expect(throws: AnalysisFailure.self) {
            try DuplicateDetector().detect(
                [file("A", Array(repeating: "same", count: 20))],
                options: AnalysisOptions(minimumDuplicateLines: 2, maximumDuplicateComparisons: 1)
            )
        }
    }
    @Test func exhaustiveShortCloneUnionMatchesBruteForce() throws {
        // Every binary sequence through length 9; minimum two-line non-overlapping matches.
        for length in 2...9 {
            for mask in 0..<(1 << length) {
                let lines = (0..<length).map { (mask >> $0) & 1 == 0 ? "a" : "b" }
                var expected: Set<Int> = []
                for first in 0..<(length - 1) {
                    for second in (first + 2)..<max(first + 2, length - 1) {
                        if lines[first] == lines[second] && lines[first + 1] == lines[second + 1] {
                            expected.formUnion([first, first + 1, second, second + 1])
                        }
                    }
                }
                let actual = try DuplicateDetector().detect(
                    [file("A", lines)], options: AnalysisOptions(minimumDuplicateLines: 2)
                )
                #expect(actual.uniqueLines == expected.count, "sequence: \(lines)")
            }
        }
    }

    private func file(_ name: String, _ lines: [String]) -> ParsedSource {
        ParsedSource(
            path: name, module: "Tests", types: [], functions: [],
            lines: lines.enumerated().map { CodeLine(number: $0.offset + 1, signature: $0.element) },
            topLevelVariables: 0, diagnostics: [])
    }
}
