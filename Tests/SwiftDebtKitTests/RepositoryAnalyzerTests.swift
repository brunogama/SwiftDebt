import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("R2 deterministic repository analysis")
struct RepositoryAnalyzerTests {
    @Test("Positive repository shapes produce evidence-rich Research detections")
    func positiveRepositoryDetections() throws {
        let report = try RepositoryAnalyzer().analyze(try fixtureSources("Positive"))

        #expect(report.schemaVersion == 1)
        #expect(report.reportKind == "swiftdebt-repository-evidence")
        #expect(report.isComplete)
        #expect(report.rules.map(\.qualification) == [.research, .research])
        #expect(report.rules.map(\.detections.count) == [1, 1])
        #expect(report.summary.detectionCount == 2)
        #expect(report.snapshot.versionControl == nil)
        for detection in report.detections {
            #expect(!detection.explanation.decisiveFacts.isEmpty)
            #expect(detection.explanation.comparedUnits.count >= 2)
            #expect(!detection.explanation.refactoringDirection.isEmpty)
            #expect(detection.explanation.documentationURL.hasPrefix("https://"))
            #expect(report.detection(for: detection.selector) == detection)
        }
    }

    @Test("Adversarial near misses prove absence only inside the exact declared scope")
    func adversarialNearMisses() throws {
        let report = try RepositoryAnalyzer().analyze(try fixtureSources("Adversarial"))

        #expect(report.isComplete)
        #expect(report.detections.isEmpty)
        #expect(report.rules.allSatisfy { $0.provesAbsence })
    }

    @Test("Input ordering does not change repository evidence bytes")
    func deterministicInputOrdering() throws {
        let sources = try fixtureSources("Positive")
        let first = try RepositoryAnalyzer().analyze(sources)
        let second = try RepositoryAnalyzer().analyze(Array(sources.reversed()))

        #expect(try RepositoryEvidenceRenderer().json(first) == RepositoryEvidenceRenderer().json(second))
    }

    @Test("Conditional switch cases make only Repeated Switches incomplete")
    func conditionalSwitchCasesAreIncomplete() throws {
        let report = try RepositoryAnalyzer().analyze(try fixtureSources("Conditional"))
        let dataClumps = try #require(report.rules.first)
        let repeatedSwitches = try #require(report.rules.last)

        #expect(!report.isComplete)
        #expect(dataClumps.completionState == .complete)
        #expect(dataClumps.provesAbsence)
        #expect(repeatedSwitches.completionState == .incomplete)
        #expect(!repeatedSwitches.provesAbsence)
        #expect(repeatedSwitches.issues.map(\.code) == ["conditional-switch-cases-unavailable"])
    }

    @Test("Parse failure makes both repository rules incomplete")
    func parseFailureIsNotClean() throws {
        let report = try RepositoryAnalyzer().analyze([
            SourceUnit(path: "Broken.swift", content: "func broken( {")
        ])

        #expect(!report.isComplete)
        #expect(report.rules.allSatisfy { $0.completionState == .incomplete })
        #expect(report.rules.allSatisfy { !$0.provesAbsence })
        #expect(report.rules.allSatisfy { $0.issues.map(\.code) == ["parse-failed"] })
    }

    @Test("Comparison budget exhaustion is explicit and cannot prove absence")
    func comparisonBudgetExhaustion() throws {
        let configuration = try RepositoryAnalysisConfiguration(
            minimumDataClumpElements: 3,
            minimumDataClumpOccurrences: 2,
            minimumRepeatedSwitchOccurrences: 2,
            maximumSourceFiles: 100,
            maximumTotalSourceBytes: 1_000_000,
            maximumAnalysisUnitsPerRule: 100,
            maximumDataClumpComparisons: 1,
            maximumDetectionsPerRule: 100
        )
        let report = try RepositoryAnalyzer().analyze(
            try fixtureSources("Positive"),
            configuration: configuration
        )
        let dataClumps = try #require(report.rules.first)

        #expect(dataClumps.completionState == .incomplete)
        #expect(!dataClumps.provesAbsence)
        #expect(dataClumps.issues.map(\.code) == ["comparison-budget-exceeded"])
        #expect(report.rules.last?.completionState == .complete)
    }

    @Test("Stored properties with observers participate while computed properties do not")
    func propertyStorageClassification() throws {
        let report = try RepositoryAnalyzer().analyze([
            SourceUnit(
                path: "ObservedProperties.swift",
                content: """
                    struct Address {
                        var customerID: String { didSet {} }
                        var postalCode: String { willSet {} }
                        let countryCode: String
                        var computed: String { customerID }
                    }

                    func deliver(customerID: String, postalCode: String, countryCode: String) {}
                    """
            )
        ])
        let detection = try #require(report.rules.first?.detections.first)
        let shared = try #require(
            detection.explanation.decisiveFacts.first { $0.kind == "shared-elements" }
        )

        #expect(shared.value == "countryCode: String, customerID: String, postalCode: String")
        #expect(!shared.value.contains("computed"))
    }

    @Test("Portable SHA-256 matches published single-block and multi-block vectors")
    func sha256Vectors() {
        #expect(
            RepositorySHA256.hex("abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        #expect(
            RepositorySHA256.hex(
                "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
            ) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
    }

    private func fixtureSources(_ name: String) throws -> [SourceUnit] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RepositoryAnalysis/\(name)")
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey]
        ).filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { url in
            SourceUnit(
                path: url.lastPathComponent,
                content: try String(contentsOf: url, encoding: .utf8)
            )
        }
    }
}
