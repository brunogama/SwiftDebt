import Foundation
import Testing

@testable import SwiftDebtCore

@Suite("Pipeline Codable models")
struct PipelineCodableTests {
    @Test("Raw-value enums round-trip every case")
    func enumsRoundTrip() throws {
        try expectRoundTrip([PipelineRisk.low, .medium, .high, .critical])
        try expectRoundTrip([PipelineTrigger.pullRequest, .scheduled])
        try expectRoundTrip([PipelineImpact.known, .uncertain])
        try expectRoundTrip(PipelineCheck.allCases)
        try expectRoundTrip([
            PipelineCheckStatus.passed,
            .failed,
            .unavailable,
            .timedOut,
        ])
        try expectRoundTrip([PipelineVerdict.passed, .failed, .inconclusive])
    }

    @Test("Canonical plans and evidence round-trip while evaluations encode")
    func modelTreesPreserveTheirSupportedCodingContracts() throws {
        let plan = pipelineTestCanonicalPlan(
            context: PipelineContext(
                risk: .critical,
                trigger: .scheduled,
                impact: .uncertain
            ))
        let results = plan.requirements.map {
            PipelineCheckResult(
                check: $0.check,
                status: .passed,
                detail: "The configured command passed."
            )
        }
        let evaluation = PipelineEvaluator.evaluate(plan: plan, results: results)
        let requirement = try #require(plan.requirements.first)
        let checkResult = try #require(results.first)

        try expectRoundTrip(plan.context)
        try expectRoundTrip(requirement)
        try expectRoundTrip(plan)
        try expectRoundTrip(checkResult)

        let encoded = try JSONEncoder().encode(evaluation)
        let observed = try JSONDecoder().decode(EncodedEvaluation.self, from: encoded)
        #expect(observed == EncodedEvaluation(verdict: .passed, results: results))
    }
}

private struct EncodedEvaluation: Decodable, Equatable {
    let verdict: PipelineVerdict
    let results: [PipelineCheckResult]
}

private func expectRoundTrip<Value: Codable & Equatable>(_ value: Value) throws {
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(Value.self, from: data)
    #expect(decoded == value)
}
