@testable import SwiftDebtCore

enum PipelinePlanTestMutation: String, CaseIterable, Sendable {
    case unsupportedPolicyRevision
    case mismatchedContext
    case emptyRequirements
    case duplicateRequirement
    case reorderedRequirements
    case weakenedRequirement
    case rewrittenReason
}

let pipelinePlanTestMutations = PipelinePlanTestMutation.allCases

func pipelineTestCanonicalPlan(
    context: PipelineContext = PipelineContext(
        risk: .low,
        trigger: .pullRequest,
        impact: .known
    )
) -> PipelinePlan {
    PipelinePlanner.plan(context: context)
}

func pipelineTestPlan(mutating mutation: PipelinePlanTestMutation) -> PipelinePlan {
    let canonical = pipelineTestCanonicalPlan()
    var policyRevision = canonical.policyRevision
    var context = canonical.context
    var requirements = canonical.requirements

    switch mutation {
    case .unsupportedPolicyRevision:
        policyRevision += 1
    case .mismatchedContext:
        context = PipelineContext(risk: .high, trigger: .pullRequest, impact: .known)
    case .emptyRequirements:
        requirements = []
    case .duplicateRequirement:
        requirements.append(requirements[0])
    case .reorderedRequirements:
        requirements.swapAt(0, 1)
    case .weakenedRequirement:
        let original = requirements[0]
        requirements[0] = PipelineRequirement(
            check: original.check,
            required: false,
            reason: original.reason
        )
    case .rewrittenReason:
        let original = requirements[0]
        requirements[0] = PipelineRequirement(
            check: original.check,
            required: original.required,
            reason: "Untrusted replacement reason."
        )
    }

    return PipelinePlan(
        policyRevision: policyRevision,
        context: context,
        requirements: requirements
    )
}
