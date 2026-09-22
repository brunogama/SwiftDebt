import Foundation
import SwiftDebtCore
import SwiftDebtKit
import Testing

@Suite("Repository dogfood CLI workflows")
struct DogfoodWorkflowTests {
    @Test("Native JSON analyzes every checked-in SwiftDebtCore source deterministically")
    func nativeJSONSelfAnalysisIsCompleteAndDeterministic() throws {
        let arguments = [
            "analyze", "Sources/SwiftDebtCore", "--format", "json", "--jobs", "1",
        ]

        let first = try runDogfoodSwiftDebt(arguments)
        let second = try runDogfoodSwiftDebt(arguments)
        try #require(first.status == 0, "stderr: \(first.standardError)")
        try #require(second.status == 0, "stderr: \(second.standardError)")
        let report = try JSONDecoder().decode(AnalysisReport.self, from: first.stdout)
        let expectedInputs = try swiftDebtCoreSourceNames()

        #expect(first.stderr.isEmpty)
        #expect(second.stderr.isEmpty)
        #expect(first.stdout == second.stdout)
        #expect(report.schemaVersion == 2)
        #expect(report.complete)
        #expect(report.inputFiles == expectedInputs)
        #expect(report.inputFileCount == expectedInputs.count)
        #expect(report.analyzedFileCount == expectedInputs.count)
        #expect(report.modules == ["Workspace"])
        #expect(report.metrics.map(\.metric) == Metric.allCases)
        #expect(report.diagnostics.isEmpty)
    }

    @Test("Ranked debt JSON analyzes repository sources with frozen Git recency")
    func rankedDebtSelfAnalysisUsesFrozenReferenceTime() throws {
        let referenceTime = "2100-01-01T00:00:00Z"
        let result = try runDogfoodSwiftDebt([
            "debt", "analyze", ".",
            "--exclude", "Tests",
            "--exclude", "Examples",
            "--exclude", "Plugins",
            "--format", "json",
            "--top", "10",
            "--jobs", "1",
            "--debt-reference-time", referenceTime,
        ])
        try #require(result.status == 0, "stderr: \(result.standardError)")
        let report = try JSONDecoder().decode(DebtReport.self, from: result.stdout)
        let recencyEvidence = report.items
            .flatMap(\.evidence)
            .filter { $0.kind == "git-history.recency" }

        #expect(result.stderr.isEmpty)
        #expect(report.schemaVersion == DebtReportSchema.currentVersion)
        #expect(report.reportKind == "swiftdebt-report")
        #expect(report.generator == "SwiftDebt")
        #expect(report.options.top == 10)
        #expect(report.summary.totalItemCount > 0)
        #expect(report.items.count == min(report.summary.totalItemCount, 10))
        #expect(report.items.allSatisfy { $0.location.file?.hasPrefix("Sources/") == true })
        #expect(recencyEvidence.count == report.items.count)
        #expect(recencyEvidence.allSatisfy { $0.availability.isAvailable })
        #expect(recencyEvidence.allSatisfy { $0.rawValue.contains("referenceTime=\(referenceTime)") })
        #expect(!report.missingEvidence.contains { $0.kind.hasPrefix("git-history.") })
    }

    @Test("Profiling emits the documented machine-readable phase schema")
    func profilingSelfAnalysisEmitsPhaseSchema() throws {
        let directory = try makeDogfoodTemporaryDirectory(named: "profile")
        defer { try? FileManager.default.removeItem(at: directory) }
        let profileURL = directory.appendingPathComponent("profile.json")

        let result = try runDogfoodSwiftDebt([
            "analyze", "Sources/SwiftDebtCore",
            "--format", "json",
            "--jobs", "1",
            "--profile-output", profileURL.path,
        ])
        try #require(result.status == 0, "stderr: \(result.standardError)")
        let report = try JSONDecoder().decode(AnalysisReport.self, from: result.stdout)
        let profile = try JSONDecoder().decode(AnalysisProfile.self, from: Data(contentsOf: profileURL))

        #expect(result.stderr.isEmpty)
        #expect(report.complete)
        #expect(profile.schemaVersion == 1)
        #expect(profile.measurements == ["wall-clock-nanoseconds", "peak-resident-memory-bytes"])
        #expect(profile.disabledOverhead.clockReads == 0)
        #expect(profile.disabledOverhead.peakMemoryReads == 0)
        #expect(profile.disabledOverhead.perSourceWork == 0)
        #expect(
            profile.phases.map(\.phase) == [
                .discovery,
                .parsing,
                .structuralEvidence,
                .graph,
                .functionalEvidence,
                .scoring,
                .aggregation,
                .rendering,
            ])
        #expect(profile.phases.allSatisfy { $0.elapsedNanoseconds > 0 })
        #expect(profile.phases.allSatisfy { ($0.peakResidentMemoryBytes ?? 0) > 0 })
    }

    private func swiftDebtCoreSourceNames() throws -> [String] {
        let directory = dogfoodRepositoryRoot.appendingPathComponent("Sources/SwiftDebtCore")
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        .filter { url in
            url.pathExtension == "swift"
                && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        .map(\.lastPathComponent)
        .sorted()
    }
}
