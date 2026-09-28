public struct DebtScoring: Sendable {
    public let policy: DebtScoringPolicy

    public init(policy: DebtScoringPolicy = DebtScoringPolicy()) {
        self.policy = policy
    }

    public func score(_ item: DebtItem) -> DebtScore {
        score(evidence: item.evidence)
    }

    public func score(evidence: [DebtEvidence]) -> DebtScore {
        let orderedEvidence = evidence.sorted(by: isOrderedBefore)
        let totalConfiguredWeight = orderedEvidence.reduce(0.0) { partial, evidence in
            partial + positiveWeight(evidence.weight)
        }
        let partition = partitionDebtEvidence(orderedEvidence)
        let dampeners = partition.available.filter { isScoreDampener($0.evidence) }
        let primaryEvidence = partition.available.filter { !isScoreDampener($0.evidence) }
        let totalAvailableWeight = primaryEvidence.reduce(0.0) {
            $0 + positiveWeight($1.evidence.weight)
        }
        var contributions = scoreContributions(
            primaryEvidence, totalAvailableWeight: totalAvailableWeight)
        guard !partition.hasUnavailableRequiredEvidence, totalAvailableWeight > 0 else {
            return DebtScore(
                value: nil,
                priority: nil,
                breakdown: DebtScoreBreakdown(
                    totalConfiguredWeight: totalConfiguredWeight,
                    totalAvailableWeight: totalAvailableWeight,
                    contributions: contributions
                        + dampenerContributions(dampeners, startingValue: nil),
                    unavailableEvidence: partition.unavailable
                )
            )
        }
        let baseValue = contributions.reduce(0.0) { $0 + $1.contribution }
        let dampenerContributions = dampenerContributions(dampeners, startingValue: baseValue)
        contributions += dampenerContributions
        let value = max(0, baseValue + dampenerContributions.reduce(0.0) { $0 + $1.contribution })
        return DebtScore(
            value: value,
            priority: policy.priorityThresholds.classify(value),
            breakdown: DebtScoreBreakdown(
                totalConfiguredWeight: totalConfiguredWeight,
                totalAvailableWeight: totalAvailableWeight,
                contributions: contributions,
                unavailableEvidence: partition.unavailable
            )
        )
    }
}
