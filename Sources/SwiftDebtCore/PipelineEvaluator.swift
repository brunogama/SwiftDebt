/// Normalizes command evidence and derives the plan verdict.
public enum PipelineEvaluator {
    public static func evaluate(
        plan: PipelinePlan,
        results: [PipelineCheckResult]
    ) -> PipelineEvaluation {
        guard plan.isCanonical else {
            return PipelineEvaluation(verdict: .inconclusive, results: [])
        }

        let normalized = plan.requirements.map { requirement in
            normalizedResult(for: requirement.check, results: results)
        }

        let requiredStatuses = zip(plan.requirements, normalized).compactMap {
            requirement, result in
            requirement.required ? result.status : nil
        }

        let verdict: PipelineVerdict
        if requiredStatuses.contains(where: { $0 == .failed || $0 == .timedOut }) {
            verdict = .failed
        } else if requiredStatuses.contains(.unavailable) {
            verdict = .inconclusive
        } else {
            verdict = .passed
        }

        return PipelineEvaluation(verdict: verdict, results: normalized)
    }

    private static func normalizedResult(
        for check: PipelineCheck,
        results: [PipelineCheckResult]
    ) -> PipelineCheckResult {
        let matchingResults = results.filter { $0.check == check }
        guard matchingResults.count == 1, let result = matchingResults.first else {
            let detail: String
            if matchingResults.isEmpty {
                detail = "No result was provided for this planned check."
            } else {
                detail = "Multiple results were provided for this planned check."
            }
            return PipelineCheckResult(check: check, status: .unavailable, detail: detail)
        }
        return result
    }
}
