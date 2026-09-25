import Foundation
import SwiftDebtCore
import Testing

@Suite("Absolute peak-memory performance headroom")
struct PerformanceBudgetMemoryHeadroomTests {
    @Test("The exact PR 62 artifact stays within a fixed two MiB process allowance")
    func exactPR62ArtifactPasses() throws {
        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: benchmark(wallClock: 0.027_048_042, memory: 10_706_944),
            candidate: benchmark(wallClock: 0.028_160_812_5, memory: 12_484_608),
            budget: budget(maximumPeakMemoryRegressionBytes: 2_097_152)
        )

        #expect(evaluation.comparable)
        #expect(evaluation.passed)
        #expect(abs(try #require(evaluation.wallClockRegressionPercent) - 4.114_051_952_448_161) < 0.000_001)
        #expect(abs(try #require(evaluation.peakMemoryRegressionPercent) - 16.602_907_421_576_13) < 0.000_001)
        #expect(evaluation.peakMemoryRegressionBytes == 1_777_664)
        #expect(evaluation.reasons.isEmpty)
    }

    @Test("A peak-memory regression one byte above both limits fails")
    func regressionAboveBothLimitsFails() {
        let baselineMemory: UInt64 = 10_706_944
        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: benchmark(memory: baselineMemory),
            candidate: benchmark(memory: baselineMemory + 2_097_153),
            budget: budget(maximumPeakMemoryRegressionBytes: 2_097_152)
        )

        #expect(!evaluation.passed)
        #expect(evaluation.peakMemoryRegressionBytes == 2_097_153)
        #expect(
            evaluation.reasons == [
                "peak-memory regression exceeds 15.0% and 2097152 bytes (observed 2097153 bytes)"
            ]
        )
    }

    @Test("Exceeding only the absolute limit does not fail the combined gate")
    func regressionBelowPercentageLimitPasses() {
        let baselineMemory: UInt64 = 100_000_000
        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: benchmark(memory: baselineMemory),
            candidate: benchmark(memory: baselineMemory + 2_097_153),
            budget: budget(maximumPeakMemoryRegressionBytes: 2_097_152)
        )

        #expect(evaluation.passed)
        #expect(evaluation.peakMemoryRegressionBytes == 2_097_153)
        #expect(evaluation.reasons.isEmpty)
    }

    @Test("Legacy budgets preserve percentage-only memory enforcement")
    func legacyBudgetDefaultsToZeroBytes() throws {
        let data = Data(
            #"{"name":"legacy","maximumWallClockRegressionPercent":10,"maximumPeakMemoryRegressionPercent":15}"#
                .utf8
        )

        let decoded = try JSONDecoder().decode(PerformanceRegressionBudget.self, from: data)

        #expect(decoded.maximumWallClockRegressionSeconds == 0)
        #expect(decoded.maximumPeakMemoryRegressionBytes == 0)
    }

    @Test("Legacy evaluations decode without an observed byte delta")
    func legacyEvaluationDefaultsToNoByteDelta() throws {
        let data = Data(
            #"{"comparable":true,"passed":false,"wallClockRegressionPercent":4.1,"peakMemoryRegressionPercent":16.6,"reasons":["peak-memory regression exceeds 15.0%"]}"#
                .utf8
        )

        let decoded = try JSONDecoder().decode(PerformanceBudgetEvaluation.self, from: data)

        #expect(decoded.peakMemoryRegressionBytes == nil)
        #expect(decoded.reasons == ["peak-memory regression exceeds 15.0%"])
    }

    private func benchmark(
        wallClock: Double = 1,
        memory: UInt64
    ) -> PerformanceBenchmarkResult {
        PerformanceBenchmarkResult(
            workload: PerformanceWorkloadIdentity(
                analyzer: "SwiftDebt",
                workloadFamily: "SwiftDebt",
                inputSHA256: "frozen-input",
                commandFingerprint: "swift-debt analyze frozen-examples --format json --jobs 1",
                analysisMode: "baseline",
                optionalContext: "none"
            ),
            wallClockSecondsMedian: wallClock,
            peakMemoryBytesMedian: memory,
            pairGenerationID: "paired-run"
        )
    }

    private func budget(
        maximumPeakMemoryRegressionBytes: UInt64
    ) -> PerformanceRegressionBudget {
        PerformanceRegressionBudget(
            name: "baseline-analysis",
            maximumWallClockRegressionPercent: 10,
            maximumPeakMemoryRegressionPercent: 15,
            maximumWallClockRegressionSeconds: 0.010,
            maximumPeakMemoryRegressionBytes: maximumPeakMemoryRegressionBytes
        )
    }
}
