/// Derives a fixed-order verification policy from explicit context.
public enum PipelinePlanner {
    private static let universalReasons: [PipelineCheck: String] = [
        .staticAnalysis: "Static analysis is required for every pipeline.",
        .architecture: "Architecture checks are required for every pipeline.",
        .unit: "Unit tests are required for every pipeline.",
        .integration: "Integration tests are required for every pipeline.",
        .endToEnd: "End-to-end tests are required for every pipeline.",
    ]

    public static func plan(context: PipelineContext) -> PipelinePlan {
        let requirements = PipelineCheck.allCases.compactMap {
            requirement(for: $0, context: context)
        }
        return PipelinePlan(
            policyRevision: PipelinePlan.currentPolicyRevision,
            context: context,
            requirements: requirements
        )
    }

    private static func requirement(
        for check: PipelineCheck,
        context: PipelineContext
    ) -> PipelineRequirement? {
        switch check {
        case .staticAnalysis, .architecture, .unit, .integration, .endToEnd:
            return universalReasons[check].map { required(check, $0) }
        case .regression:
            return regressionRequirement(context: context)
        case .fullRegression:
            return fullRegressionRequirement(context: context)
        case .property:
            return propertyRequirement(context: context)
        case .mutation:
            return mutationRequirement(context: context)
        case .dynamicAnalysis:
            return dynamicAnalysisRequirement(context: context)
        case .dependencies:
            guard context.trigger == .scheduled else { return nil }
            return required(check, "Scheduled pipelines require dependency checks.")
        }
    }

    private static func regressionRequirement(
        context: PipelineContext
    ) -> PipelineRequirement? {
        guard context.trigger == .pullRequest, context.impact == .known else { return nil }
        return required(
            .regression,
            "A pull request with known impact requires targeted regression tests."
        )
    }

    private static func fullRegressionRequirement(
        context: PipelineContext
    ) -> PipelineRequirement? {
        if context.trigger == .scheduled {
            return required(.fullRegression, "Scheduled pipelines require full regression tests.")
        }
        guard context.impact == .uncertain else { return nil }
        return required(
            .fullRegression,
            "A pull request with uncertain impact requires full regression tests."
        )
    }

    private static func propertyRequirement(
        context: PipelineContext
    ) -> PipelineRequirement? {
        if context.trigger == .scheduled {
            return required(.property, "Scheduled pipelines require property tests.")
        }
        guard requiresRiskChecks(context.risk) else { return nil }
        return required(.property, "High or critical risk requires property tests.")
    }

    private static func mutationRequirement(
        context: PipelineContext
    ) -> PipelineRequirement? {
        guard context.trigger == .scheduled || requiresRiskChecks(context.risk) else { return nil }
        return advisory(
            .mutation,
            "Mutation testing supplies advisory evidence for elevated pipeline contexts."
        )
    }

    private static func dynamicAnalysisRequirement(
        context: PipelineContext
    ) -> PipelineRequirement? {
        if context.trigger == .scheduled {
            return required(.dynamicAnalysis, "Scheduled pipelines require dynamic analysis.")
        }
        guard requiresRiskChecks(context.risk) else { return nil }
        return advisory(
            .dynamicAnalysis,
            "Dynamic analysis supplies advisory evidence for high or critical risk."
        )
    }

    private static func required(
        _ check: PipelineCheck,
        _ reason: String
    ) -> PipelineRequirement {
        PipelineRequirement(check: check, required: true, reason: reason)
    }

    private static func advisory(
        _ check: PipelineCheck,
        _ reason: String
    ) -> PipelineRequirement {
        PipelineRequirement(check: check, required: false, reason: reason)
    }

    private static func requiresRiskChecks(_ risk: PipelineRisk) -> Bool {
        risk == .high || risk == .critical
    }
}
