import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("R2 repository analysis budgets")
struct RepositoryAnalyzerBudgetTests {
    @Test("Source budgets fail before repository snapshot hashing")
    func sourceBudgetsFailBeforeSnapshotHashing() throws {
        let fileLimited = try RepositoryAnalysisConfiguration(
            minimumDataClumpElements: 3,
            minimumDataClumpOccurrences: 2,
            minimumRepeatedSwitchOccurrences: 2,
            maximumSourceFiles: 1,
            maximumTotalSourceBytes: 1_000_000,
            maximumAnalysisUnitsPerRule: 100,
            maximumDataClumpComparisons: 1_000,
            maximumDetectionsPerRule: 100
        )
        let byteLimited = try RepositoryAnalysisConfiguration(
            minimumDataClumpElements: 3,
            minimumDataClumpOccurrences: 2,
            minimumRepeatedSwitchOccurrences: 2,
            maximumSourceFiles: 100,
            maximumTotalSourceBytes: 1,
            maximumAnalysisUnitsPerRule: 100,
            maximumDataClumpComparisons: 1_000,
            maximumDetectionsPerRule: 100
        )
        let sources = [
            SourceUnit(path: "First.swift", content: "func first() {}"),
            SourceUnit(path: "Second.swift", content: "func second() {}"),
        ]

        #expect(throws: RepositoryAnalysisFailure.sourceFileBudgetExceeded(selected: 2, limit: 1)) {
            try RepositoryAnalyzer().analyze(sources, configuration: fileLimited)
        }
        #expect(throws: RepositoryAnalysisFailure.sourceByteBudgetExceeded(selected: 31, limit: 1)) {
            try RepositoryAnalyzer().analyze(sources, configuration: byteLimited)
        }
    }

    @Test("Support scans and closure intersections consume the comparison budget")
    func comparisonBudgetCountsCandidateRescans() throws {
        let functions = (0..<8).map { index in
            """
            func operation\(index)(customerID: String, postalCode: String, countryCode: String) {}
            """
        }.joined(separator: "\n")
        let configuration = try RepositoryAnalysisConfiguration(
            minimumDataClumpElements: 3,
            minimumDataClumpOccurrences: 2,
            minimumRepeatedSwitchOccurrences: 2,
            maximumSourceFiles: 100,
            maximumTotalSourceBytes: 1_000_000,
            maximumAnalysisUnitsPerRule: 100,
            maximumDataClumpComparisons: 15,
            maximumDetectionsPerRule: 100
        )

        let report = try RepositoryAnalyzer().analyze(
            [
                SourceUnit(path: "ManyOverlaps.swift", content: functions)
            ], configuration: configuration)
        let dataClumps = try #require(report.rules.first)

        #expect(dataClumps.completionState == .incomplete)
        #expect(dataClumps.detections.isEmpty)
        #expect(!dataClumps.provesAbsence)
        #expect(dataClumps.issues.map(\.code) == ["comparison-budget-exceeded"])
    }

    @Test("Unit budgets cap syntax fact materialization before rule analysis")
    func unitBudgetsCapFactMaterialization() {
        let functions = (0..<20).map { index in
            "func operation\(index)(a: Int, b: Int, c: Int) {}"
        }.joined(separator: "\n")
        let switches = (0..<20).map { index in
            """
            func switchOperation\(index)(_ value: Bool) {
                switch value {
                case true: break
                case false: break
                }
            }
            """
        }.joined(separator: "\n")

        let facts = RepositorySyntaxExtractor().extract(
            [SourceUnit(path: "Bounded.swift", content: functions + "\n" + switches)],
            maximumAnalysisUnitsPerRule: 1
        )

        #expect(facts.dataClumpUnits.count == 2)
        #expect(facts.repeatedSwitchUnits.count == 2)
    }

    @Test("Detection budgets bound materialization and make both affected rules incomplete")
    func detectionBudgetsAreIncomplete() throws {
        let source = """
            func firstA(customerID: String, postalCode: String, countryCode: String) {}
            func firstB(customerID: String, postalCode: String, countryCode: String) {}
            func secondA(latitude: Double, longitude: Double, altitude: Double) {}
            func secondB(latitude: Double, longitude: Double, altitude: Double) {}

            enum Mode { case first, second }

            struct SwitchOwner {
                let primary: Mode
                let secondary: Mode

                func primaryA() {
                    switch primary {
                    case .first: break
                    case .second: break
                    }
                }

                func primaryB() {
                    switch primary {
                    case .first: break
                    case .second: break
                    }
                }

                func secondaryA() {
                    switch secondary {
                    case .first: break
                    case .second: break
                    }
                }

                func secondaryB() {
                    switch secondary {
                    case .first: break
                    case .second: break
                    }
                }
            }
            """
        let configuration = try RepositoryAnalysisConfiguration(
            minimumDataClumpElements: 3,
            minimumDataClumpOccurrences: 2,
            minimumRepeatedSwitchOccurrences: 2,
            maximumSourceFiles: 100,
            maximumTotalSourceBytes: 1_000_000,
            maximumAnalysisUnitsPerRule: 100,
            maximumDataClumpComparisons: 10_000,
            maximumDetectionsPerRule: 1
        )

        let report = try RepositoryAnalyzer().analyze(
            [
                SourceUnit(path: "DetectionBudget.swift", content: source)
            ], configuration: configuration)

        #expect(report.rules.allSatisfy { $0.completionState == .incomplete })
        #expect(report.rules.allSatisfy { $0.detections.count == 1 })
        #expect(report.rules.allSatisfy { $0.issues.map(\.code) == ["detection-budget-exceeded"] })
    }
}
