import Testing

@testable import SwiftDebtCore

@Suite("Pipeline planner")
struct PipelinePlannerTests {
    @Test("Plans every risk, trigger, and impact combination", arguments: plannerScenarios)
    private func plansFullMatrix(scenario: PlannerScenario) {
        let plan = PipelinePlanner.plan(context: scenario.context)
        let actual = plan.requirements.map {
            ExpectedRequirement(check: $0.check, required: $0.required)
        }

        #expect(plan.policyRevision == 1)
        #expect(plan.context == scenario.context)
        #expect(actual == scenario.expected)
        #expect(plan.requirements.allSatisfy { !$0.reason.isEmpty })

        for requirement in plan.requirements {
            #expect(plan.requirements.filter { $0.check == requirement.check }.count == 1)
        }
    }

    @Test("The matrix covers all sixteen contexts")
    func matrixIsComplete() {
        #expect(plannerScenarios.count == 16)
    }
}

private struct PlannerScenario: Sendable {
    let context: PipelineContext
    let expected: [ExpectedRequirement]
}

private struct ExpectedRequirement: Equatable, Sendable {
    let check: PipelineCheck
    let required: Bool
}

private func expected(
    _ check: PipelineCheck,
    required: Bool = true
) -> ExpectedRequirement {
    ExpectedRequirement(check: check, required: required)
}

private let knownPullRequest = [
    expected(.staticAnalysis),
    expected(.architecture),
    expected(.unit),
    expected(.integration),
    expected(.regression),
    expected(.endToEnd),
]

private let uncertainPullRequest = [
    expected(.staticAnalysis),
    expected(.architecture),
    expected(.unit),
    expected(.integration),
    expected(.fullRegression),
    expected(.endToEnd),
]

private let elevatedKnownPullRequest = [
    expected(.staticAnalysis),
    expected(.architecture),
    expected(.unit),
    expected(.integration),
    expected(.regression),
    expected(.endToEnd),
    expected(.property),
    expected(.mutation, required: false),
    expected(.dynamicAnalysis, required: false),
]

private let elevatedUncertainPullRequest = [
    expected(.staticAnalysis),
    expected(.architecture),
    expected(.unit),
    expected(.integration),
    expected(.fullRegression),
    expected(.endToEnd),
    expected(.property),
    expected(.mutation, required: false),
    expected(.dynamicAnalysis, required: false),
]

private let scheduled = [
    expected(.staticAnalysis),
    expected(.architecture),
    expected(.unit),
    expected(.integration),
    expected(.fullRegression),
    expected(.endToEnd),
    expected(.property),
    expected(.mutation, required: false),
    expected(.dynamicAnalysis),
    expected(.dependencies),
]

private let plannerScenarios = [
    PlannerScenario(
        context: PipelineContext(risk: .low, trigger: .pullRequest, impact: .known),
        expected: knownPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .low, trigger: .pullRequest, impact: .uncertain),
        expected: uncertainPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .low, trigger: .scheduled, impact: .known),
        expected: scheduled),
    PlannerScenario(
        context: PipelineContext(risk: .low, trigger: .scheduled, impact: .uncertain),
        expected: scheduled),
    PlannerScenario(
        context: PipelineContext(risk: .medium, trigger: .pullRequest, impact: .known),
        expected: knownPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .medium, trigger: .pullRequest, impact: .uncertain),
        expected: uncertainPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .medium, trigger: .scheduled, impact: .known),
        expected: scheduled),
    PlannerScenario(
        context: PipelineContext(risk: .medium, trigger: .scheduled, impact: .uncertain),
        expected: scheduled),
    PlannerScenario(
        context: PipelineContext(risk: .high, trigger: .pullRequest, impact: .known),
        expected: elevatedKnownPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .high, trigger: .pullRequest, impact: .uncertain),
        expected: elevatedUncertainPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .high, trigger: .scheduled, impact: .known),
        expected: scheduled),
    PlannerScenario(
        context: PipelineContext(risk: .high, trigger: .scheduled, impact: .uncertain),
        expected: scheduled),
    PlannerScenario(
        context: PipelineContext(risk: .critical, trigger: .pullRequest, impact: .known),
        expected: elevatedKnownPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .critical, trigger: .pullRequest, impact: .uncertain),
        expected: elevatedUncertainPullRequest),
    PlannerScenario(
        context: PipelineContext(risk: .critical, trigger: .scheduled, impact: .known),
        expected: scheduled),
    PlannerScenario(
        context: PipelineContext(risk: .critical, trigger: .scheduled, impact: .uncertain),
        expected: scheduled),
]
