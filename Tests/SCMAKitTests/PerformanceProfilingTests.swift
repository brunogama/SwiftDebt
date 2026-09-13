import Foundation
import SCMACore
import SCMAKit
import Testing

@Suite("Performance profiling and budgets")
struct PerformanceProfilingTests {
    @Test func profilingWritesMachineReadablePhaseOutputWhenEnabled() async throws {
        let workspace = try makeWorkspace()
        let reportPath = workspace.appendingPathComponent("report.json").path
        let profilePath = workspace.appendingPathComponent("profile.json").path

        let result = try await AnalysisService().run(
            AnalysisRequest(
                path: workspace.path,
                outputPath: reportPath,
                format: .debtJSON,
                enableDebtAnalysis: true,
                lcovPath: "missing.info",
                debtReferenceTime: Date(timeIntervalSince1970: 0),
                profileOutputPath: profilePath
            )
        )

        let profile = try #require(result.profile)
        let data = try Data(contentsOf: URL(fileURLWithPath: profilePath))
        let decoded = try JSONDecoder().decode(AnalysisProfile.self, from: data)
        let phases = Set(decoded.phases.map(\.phase))

        #expect(profile.schemaVersion == 1)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.measurements == ["wall-clock-nanoseconds", "peak-resident-memory-bytes"])
        #expect(decoded.disabledOverhead.clockReads == 0)
        #expect(decoded.disabledOverhead.peakMemoryReads == 0)
        #expect(decoded.disabledOverhead.perSourceWork == 0)
        #expect(decoded.disabledOverhead.phaseBoundaryChecks == AnalysisProfile.disabledInstrumentationOverhead.phaseBoundaryChecks)
        #expect(phases.isSuperset(of: [.discovery, .parsing, .structuralEvidence, .graph, .coverage]))
        #expect(phases.isSuperset(of: [.repositoryHistory, .functionalEvidence, .scoring, .aggregation, .rendering]))
        #expect(decoded.phases.allSatisfy { $0.elapsedNanoseconds > 0 })
    }

    @Test func profilingIsAbsentByDefaultAndDisabledOverheadIsQuantified() async throws {
        let workspace = try makeWorkspace()

        let result = try await AnalysisService().run(
            AnalysisRequest(path: workspace.path, format: .json)
        )

        #expect(result.profile == nil)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.clockReads == 0)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.peakMemoryReads == 0)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.perSourceWork == 0)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.phaseBoundaryChecks >= AnalysisPhase.allCases.count * 2)
    }

    @Test func performanceGateRejectsIncomparableDebtmapRustWorkloads() {
        let baseline = PerformanceBenchmarkResult(
            workload: PerformanceWorkloadIdentity(
                analyzer: "SwiftSCMA",
                workloadFamily: "SwiftSCMA",
                inputSHA256: "swift-input",
                commandFingerprint: "scma analyze Examples/Sources --jobs 1",
                analysisMode: "baseline",
                optionalContext: "none"
            ),
            wallClockSecondsMedian: 1,
            peakMemoryBytesMedian: 100
        )
        let candidate = PerformanceBenchmarkResult(
            workload: PerformanceWorkloadIdentity(
                analyzer: "Debtmap",
                workloadFamily: "Debtmap Rust",
                inputSHA256: "rust-input",
                commandFingerprint: "debtmap analyze crates",
                analysisMode: "baseline",
                optionalContext: "none"
            ),
            wallClockSecondsMedian: 1,
            peakMemoryBytesMedian: 100
        )

        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline,
            candidate: candidate,
            budget: PerformanceRegressionBudget(
                name: "baseline-analysis",
                maximumWallClockRegressionPercent: 10,
                maximumPeakMemoryRegressionPercent: 15
            )
        )

        #expect(!evaluation.comparable)
        #expect(!evaluation.passed)
        #expect(evaluation.wallClockRegressionPercent == nil)
        #expect(evaluation.peakMemoryRegressionPercent == nil)
        #expect(evaluation.reasons.contains("analyzer differs"))
        #expect(evaluation.reasons.contains("workload family differs"))
    }

    @Test func performanceGateAppliesWallClockAndMemoryBudgetsForEquivalentWorkloads() {
        let workload = PerformanceWorkloadIdentity(
            analyzer: "SwiftSCMA",
            workloadFamily: "SwiftSCMA",
            inputSHA256: "swift-input",
            commandFingerprint: "scma analyze Examples/Sources --jobs 1",
            analysisMode: "baseline",
            optionalContext: "none"
        )
        let baseline = PerformanceBenchmarkResult(
            workload: workload,
            wallClockSecondsMedian: 10,
            peakMemoryBytesMedian: 1_000
        )
        let candidate = PerformanceBenchmarkResult(
            workload: workload,
            wallClockSecondsMedian: 11.5,
            peakMemoryBytesMedian: 1_200
        )

        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline,
            candidate: candidate,
            budget: PerformanceRegressionBudget(
                name: "baseline-analysis",
                maximumWallClockRegressionPercent: 10,
                maximumPeakMemoryRegressionPercent: 15
            )
        )

        #expect(evaluation.comparable)
        #expect(!evaluation.passed)
        #expect(evaluation.wallClockRegressionPercent == 15)
        #expect(evaluation.peakMemoryRegressionPercent == 20)
        #expect(evaluation.reasons.contains("wall-clock regression exceeds 10.0%"))
        #expect(evaluation.reasons.contains("peak-memory regression exceeds 15.0%"))
    }

    private func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftSCMAPerformanceProfiling-")
            .appendingPathComponent(UUID().uuidString)
        let sourceDirectory = workspace.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try """
        final class ProfiledExample {
            let value = 1

            func answer(_ input: Int) -> Int {
                if input > value {
                    return input
                }
                return value
            }
        }
        """.write(
            to: sourceDirectory.appendingPathComponent("Example.swift"),
            atomically: true,
            encoding: .utf8
        )
        return workspace
    }
}
