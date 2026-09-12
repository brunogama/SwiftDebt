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
        var available: [DebtEvidence] = []
        var unavailable: [DebtUnavailableEvidence] = []
        var hasUnavailableRequiredEvidence = false

        for evidence in orderedEvidence {
            let weight = positiveWeight(evidence.weight)
            guard evidence.availability.isAvailable else {
                if evidence.requirement == .required { hasUnavailableRequiredEvidence = true }
                unavailable.append(
                    DebtUnavailableEvidence(
                        evidenceID: evidence.id,
                        kind: evidence.kind,
                        requirement: evidence.requirement,
                        configuredWeight: weight,
                        reason: evidence.availability.reason
                    )
                )
                continue
            }
            guard evidence.normalizedScore != nil, weight > 0 else {
                if evidence.requirement == .required { hasUnavailableRequiredEvidence = true }
                unavailable.append(
                    DebtUnavailableEvidence(
                        evidenceID: evidence.id,
                        kind: evidence.kind,
                        requirement: evidence.requirement,
                        configuredWeight: weight,
                        reason: evidence.normalizedScore == nil ? "normalized score unavailable" : "weight is not positive"
                    )
                )
                continue
            }
            available.append(evidence)
        }

        let totalAvailableWeight = available.reduce(0.0) { $0 + positiveWeight($1.weight) }
        let contributions = available.map { evidence -> DebtScoreContribution in
            let normalizedScore = bounded(evidence.normalizedScore ?? 0)
            let effectiveWeight = positiveWeight(evidence.weight) / totalAvailableWeight
            let contribution = normalizedScore * effectiveWeight
            return DebtScoreContribution(
                evidenceID: evidence.id,
                kind: evidence.kind,
                rawValue: evidence.rawValue,
                normalizedScore: normalizedScore,
                configuredWeight: positiveWeight(evidence.weight),
                effectiveWeight: effectiveWeight,
                contribution: contribution,
                note: contributionNote(for: evidence)
            )
        }
        guard !hasUnavailableRequiredEvidence, totalAvailableWeight > 0 else {
            return DebtScore(
                value: nil,
                priority: nil,
                breakdown: DebtScoreBreakdown(
                    totalConfiguredWeight: totalConfiguredWeight,
                    totalAvailableWeight: totalAvailableWeight,
                    contributions: contributions,
                    unavailableEvidence: unavailable
                )
            )
        }
        let value = contributions.reduce(0.0) { $0 + $1.contribution }
        return DebtScore(
            value: value,
            priority: policy.priorityThresholds.classify(value),
            breakdown: DebtScoreBreakdown(
                totalConfiguredWeight: totalConfiguredWeight,
                totalAvailableWeight: totalAvailableWeight,
                contributions: contributions,
                unavailableEvidence: unavailable
            )
        )
    }
}

private func isOrderedBefore(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
    if let ordered = isOrdered(lhs.id, before: rhs.id) { return ordered }
    if let ordered = isOrdered(lhs.kind, before: rhs.kind) { return ordered }
    if let ordered = isOrdered(lhs.rawValue, before: rhs.rawValue) { return ordered }
    if let ordered = isOrdered(lhs.note, before: rhs.note) { return ordered }
    if let ordered = isOrdered(lhs.requirement.rawValue, before: rhs.requirement.rawValue) { return ordered }
    if let ordered = isOrdered(lhs.availability.state.rawValue, before: rhs.availability.state.rawValue) { return ordered }
    if let ordered = isOrdered(lhs.availability.reason, before: rhs.availability.reason) { return ordered }
    if let ordered = isOrdered(lhs.weight, before: rhs.weight) { return ordered }
    if let ordered = isOrdered(lhs.normalizedScore, before: rhs.normalizedScore) { return ordered }
    if let ordered = isOrdered(lhs.location?.module, before: rhs.location?.module) { return ordered }
    if let ordered = isOrdered(lhs.location?.file, before: rhs.location?.file) { return ordered }
    if let ordered = isOrdered(lhs.location?.line, before: rhs.location?.line) { return ordered }
    if let ordered = isOrdered(lhs.location?.column, before: rhs.location?.column) { return ordered }
    return false
}

private func isOrdered<T: Comparable>(_ lhs: T, before rhs: T) -> Bool? {
    lhs == rhs ? nil : lhs < rhs
}

private func isOrdered<T: Comparable>(_ lhs: T?, before rhs: T?) -> Bool? {
    switch (lhs, rhs) {
    case (.none, .none):
        return nil
    case (.none, .some):
        return true
    case (.some, .none):
        return false
    case let (.some(lhs), .some(rhs)):
        return isOrdered(lhs, before: rhs)
    }
}

private func isOrdered(_ lhs: Double, before rhs: Double) -> Bool? {
    if lhs.isNaN, rhs.isNaN { return nil }
    if lhs.isNaN { return true }
    if rhs.isNaN { return false }
    return lhs == rhs ? nil : lhs < rhs
}

private func isOrdered(_ lhs: Double?, before rhs: Double?) -> Bool? {
    switch (lhs, rhs) {
    case (.none, .none):
        return nil
    case (.none, .some):
        return true
    case (.some, .none):
        return false
    case let (.some(lhs), .some(rhs)):
        return isOrdered(lhs, before: rhs)
    }
}

private func positiveWeight(_ weight: Double) -> Double {
    max(0, weight)
}

private func bounded(_ score: Double) -> Double {
    min(100, max(0, score))
}

private func contributionNote(for evidence: DebtEvidence) -> String? {
    guard let note = evidence.note else {
        if let score = evidence.normalizedScore, score != bounded(score) {
            return "normalized score clamped to 0...100"
        }
        return nil
    }
    if let score = evidence.normalizedScore, score != bounded(score) {
        return note + "; normalized score clamped to 0...100"
    }
    return note
}
