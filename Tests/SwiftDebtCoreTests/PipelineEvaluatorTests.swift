import Testing

@testable import SwiftDebtCore

@Suite("Pipeline evaluator")
struct PipelineEvaluatorTests {
    @Test("Normalizes to canonical plan order and omits unplanned results")
    func normalizesAndOmitsUnplannedResults() {
        let plan = pipelineTestCanonicalPlan()
        let passing = passingResults(for: plan)
        let evaluation = PipelineEvaluator.evaluate(
            plan: plan,
            results: Array(passing.reversed()) + [result(.dependencies, .passed)]
        )

        #expect(evaluation.verdict == .passed)
        #expect(evaluation.results == passing)
    }

    @Test("Missing required evidence is inconclusive")
    func missingRequiredEvidenceIsInconclusive() {
        let plan = pipelineTestCanonicalPlan()
        let evaluation = PipelineEvaluator.evaluate(
            plan: plan,
            results: passingResults(for: plan).filter { $0.check != .unit }
        )

        #expect(evaluation.verdict == .inconclusive)
        #expect(evaluation.results.first { $0.check == .unit }?.status == .unavailable)
    }

    @Test("Duplicate evidence is unavailable")
    func duplicateEvidenceIsUnavailable() {
        let plan = pipelineTestCanonicalPlan()
        let evaluation = PipelineEvaluator.evaluate(
            plan: plan,
            results: passingResults(for: plan) + [result(.staticAnalysis, .failed)]
        )

        #expect(evaluation.verdict == .inconclusive)
        #expect(evaluation.results.first { $0.check == .staticAnalysis }?.status == .unavailable)
        #expect(
            evaluation.results.first { $0.check == .staticAnalysis }?.detail.contains("Multiple")
                == true)
    }

    @Test("Required failure takes precedence over missing evidence")
    func requiredFailureTakesPrecedence() {
        let plan = pipelineTestCanonicalPlan()
        var results = replacing(
            .staticAnalysis,
            with: .failed,
            in: passingResults(for: plan)
        )
        results.removeAll { $0.check == .architecture }

        let evaluation = PipelineEvaluator.evaluate(plan: plan, results: results)

        #expect(evaluation.verdict == .failed)
        #expect(evaluation.results.first { $0.check == .architecture }?.status == .unavailable)
    }

    @Test(
        "A failed or timed-out required check fails",
        arguments: [PipelineCheckStatus.failed, .timedOut]
    )
    func blockingStatusFails(status: PipelineCheckStatus) {
        let plan = pipelineTestCanonicalPlan()
        let evaluation = PipelineEvaluator.evaluate(
            plan: plan,
            results: replacing(.integration, with: status, in: passingResults(for: plan))
        )

        #expect(evaluation.verdict == .failed)
    }

    @Test("Explicitly unavailable required evidence is inconclusive")
    func unavailableRequiredEvidenceIsInconclusive() {
        let plan = pipelineTestCanonicalPlan()
        let evaluation = PipelineEvaluator.evaluate(
            plan: plan,
            results: replacing(.endToEnd, with: .unavailable, in: passingResults(for: plan))
        )

        #expect(evaluation.verdict == .inconclusive)
    }

    @Test(
        "Advisory outcomes remain visible without blocking",
        arguments: [PipelineCheckStatus.failed, .timedOut, .unavailable]
    )
    func advisoryEvidenceDoesNotBlock(status: PipelineCheckStatus) {
        let plan = elevatedPlan()
        let evaluation = PipelineEvaluator.evaluate(
            plan: plan,
            results: replacing(.dynamicAnalysis, with: status, in: passingResults(for: plan))
        )

        #expect(evaluation.verdict == .passed)
        #expect(evaluation.results.first { $0.check == .dynamicAnalysis }?.status == status)
    }

    @Test("A missing advisory result remains visible without blocking")
    func missingAdvisoryResultDoesNotBlock() {
        let plan = elevatedPlan()
        let evaluation = PipelineEvaluator.evaluate(
            plan: plan,
            results: passingResults(for: plan).filter { $0.check != .mutation }
        )

        #expect(evaluation.verdict == .passed)
        #expect(evaluation.results.first { $0.check == .mutation }?.status == .unavailable)
    }

    @Test("An unplanned result cannot satisfy a missing planned check")
    func unplannedResultCannotSatisfyPlan() {
        let plan = pipelineTestCanonicalPlan()
        let results =
            passingResults(for: plan).filter { $0.check != .unit }
            + [result(.dependencies, .passed)]
        let evaluation = PipelineEvaluator.evaluate(plan: plan, results: results)

        #expect(evaluation.verdict == .inconclusive)
        #expect(evaluation.results.map(\.check) == plan.requirements.map(\.check))
    }

    @Test("Invalid internal plans are rejected", arguments: pipelinePlanTestMutations)
    func invalidInternalPlanIsInconclusive(mutation: PipelinePlanTestMutation) {
        let plan = pipelineTestPlan(mutating: mutation)
        let evaluation = PipelineEvaluator.evaluate(plan: plan, results: passingResults(for: plan))

        #expect(evaluation.verdict == .inconclusive)
        #expect(evaluation.results.isEmpty)
    }

    @Test("Verdicts map to stable exit statuses")
    func mapsExitStatuses() {
        let plan = pipelineTestCanonicalPlan()
        let passing = passingResults(for: plan)
        let passed = PipelineEvaluator.evaluate(plan: plan, results: passing)
        let failed = PipelineEvaluator.evaluate(
            plan: plan,
            results: replacing(.staticAnalysis, with: .failed, in: passing)
        )
        let inconclusive = PipelineEvaluator.evaluate(
            plan: plan,
            results: passing.filter { $0.check != .staticAnalysis }
        )

        #expect([passed.exitStatus, failed.exitStatus, inconclusive.exitStatus] == [0, 1, 2])
    }
}

private func elevatedPlan() -> PipelinePlan {
    pipelineTestCanonicalPlan(
        context: PipelineContext(risk: .high, trigger: .pullRequest, impact: .known)
    )
}

private func passingResults(for plan: PipelinePlan) -> [PipelineCheckResult] {
    plan.requirements.map { result($0.check, .passed) }
}

private func replacing(
    _ check: PipelineCheck,
    with status: PipelineCheckStatus,
    in results: [PipelineCheckResult]
) -> [PipelineCheckResult] {
    results.map { $0.check == check ? result(check, status) : $0 }
}

private func result(
    _ check: PipelineCheck,
    _ status: PipelineCheckStatus,
    _ detail: String = "test"
) -> PipelineCheckResult {
    PipelineCheckResult(check: check, status: status, detail: detail)
}
