import Foundation
import SwiftDebtCore
import Testing

@Suite("Paired benchmark identity")
struct PerformancePairIdentityTests {
    @Test("A mixed-generation benchmark pair cannot pass the gate")
    func mixedGenerationsFailClosed() throws {
        let workload = PerformanceWorkloadIdentity(
            analyzer: "SwiftDebt", workloadFamily: "SwiftDebt",
            inputSHA256: "input", commandFingerprint: "command",
            analysisMode: "baseline", optionalContext: "none"
        )
        let sample = PerformanceBenchmarkResult(
            workload: workload, wallClockSecondsMedian: 1,
            peakMemoryBytesMedian: 100
        )
        let encoded = try JSONEncoder().encode(sample)
        let baseline = try decode(encoded, pairID: "generation-a")
        let candidate = try decode(encoded, pairID: "generation-b")
        let budget = PerformanceRegressionBudget(
            name: "baseline", maximumWallClockRegressionPercent: 10,
            maximumPeakMemoryRegressionPercent: 15
        )

        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline, candidate: candidate, budget: budget
        )

        #expect(!evaluation.comparable)
        #expect(!evaluation.passed)
        #expect(evaluation.reasons.contains("measurement pair generation differs"))
    }

    @Test("A matching generation is comparable, while a missing half fails closed")
    func missingHalfFailsClosed() throws {
        let sample = PerformanceBenchmarkResult(
            workload: PerformanceWorkloadIdentity(
                analyzer: "SwiftDebt", workloadFamily: "SwiftDebt",
                inputSHA256: "input", commandFingerprint: "command",
                analysisMode: "baseline", optionalContext: "none"
            ),
            wallClockSecondsMedian: 1, peakMemoryBytesMedian: 100
        )
        let paired = try decode(JSONEncoder().encode(sample), pairID: "generation-a")
        let budget = PerformanceRegressionBudget(
            name: "baseline", maximumWallClockRegressionPercent: 10,
            maximumPeakMemoryRegressionPercent: 15
        )

        #expect(
            PerformanceBudgetGate.evaluate(
                baseline: paired, candidate: paired, budget: budget
            ).passed)
        let mixed = PerformanceBudgetGate.evaluate(
            baseline: paired, candidate: sample, budget: budget
        )
        #expect(!mixed.comparable)
        #expect(mixed.reasons == ["measurement pair generation differs"])
    }

    private func decode(_ data: Data, pairID: String) throws -> PerformanceBenchmarkResult {
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["pairGenerationID"] = pairID
        return try JSONDecoder().decode(
            PerformanceBenchmarkResult.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }
}
