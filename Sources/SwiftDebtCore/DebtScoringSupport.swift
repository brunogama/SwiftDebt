typealias AvailableDebtEvidence = (evidence: DebtEvidence, normalizedScore: Double)

struct PartitionedDebtEvidence {
    var available: [AvailableDebtEvidence] = []
    var unavailable: [DebtUnavailableEvidence] = []
    var hasUnavailableRequiredEvidence = false
}

func partitionDebtEvidence(_ evidence: [DebtEvidence]) -> PartitionedDebtEvidence {
    evidence.reduce(into: PartitionedDebtEvidence()) { result, evidence in
        let weight = positiveWeight(evidence.weight)
        guard evidence.availability.isAvailable,
            let normalizedScore = evidence.normalizedScore, weight > 0
        else {
            if evidence.requirement == .required {
                result.hasUnavailableRequiredEvidence = true
            }
            result.unavailable.append(
                DebtUnavailableEvidence(
                    evidenceID: evidence.id, kind: evidence.kind,
                    requirement: evidence.requirement, configuredWeight: weight,
                    reason: evidence.availability.reason
                        ?? (evidence.normalizedScore == nil
                            ? "normalized score unavailable" : "weight is not positive")))
            return
        }
        result.available.append((evidence, normalizedScore))
    }
}

func scoreContributions(
    _ evidence: [AvailableDebtEvidence], totalAvailableWeight: Double
) -> [DebtScoreContribution] {
    evidence.map { available in
        let normalizedScore = bounded(available.normalizedScore)
        let effectiveWeight = positiveWeight(available.evidence.weight) / totalAvailableWeight
        return DebtScoreContribution(
            evidenceID: available.evidence.id, kind: available.evidence.kind,
            rawValue: available.evidence.rawValue, normalizedScore: normalizedScore,
            configuredWeight: positiveWeight(available.evidence.weight),
            effectiveWeight: effectiveWeight,
            contribution: normalizedScore * effectiveWeight,
            note: contributionNote(for: available.evidence))
    }
}

func isOrderedBefore(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
    if let ordered = evidenceIdentityOrder(lhs, rhs) { return ordered }
    if let ordered = evidenceAvailabilityOrder(lhs, rhs) { return ordered }
    if let ordered = evidenceLocationOrder(lhs, rhs) { return ordered }
    return false
}

private func evidenceIdentityOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool? {
    if let value = isOrdered(lhs.id, before: rhs.id) { return value }
    if let value = isOrdered(lhs.kind, before: rhs.kind) { return value }
    if let value = isOrdered(lhs.rawValue, before: rhs.rawValue) { return value }
    if let value = isOrdered(lhs.note, before: rhs.note) { return value }
    return isOrdered(lhs.requirement.rawValue, before: rhs.requirement.rawValue)
}

private func evidenceAvailabilityOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool? {
    if let ordered = isOrdered(
        lhs.availability.state.rawValue, before: rhs.availability.state.rawValue)
    {
        return ordered
    }
    if let ordered = isOrdered(lhs.availability.reason, before: rhs.availability.reason) {
        return ordered
    }
    if let ordered = isOrdered(lhs.weight, before: rhs.weight) { return ordered }
    return isOrdered(lhs.normalizedScore, before: rhs.normalizedScore)
}

private func evidenceLocationOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool? {
    if let ordered = isOrdered(lhs.location?.module, before: rhs.location?.module) {
        return ordered
    }
    if let ordered = isOrdered(lhs.location?.file, before: rhs.location?.file) { return ordered }
    if let ordered = isOrdered(lhs.location?.line, before: rhs.location?.line) { return ordered }
    return isOrdered(lhs.location?.column, before: rhs.location?.column)
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
    case (.some(let lhs), .some(let rhs)):
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
    case (.some(let lhs), .some(let rhs)):
        return isOrdered(lhs, before: rhs)
    }
}

func isScoreDampener(_ evidence: DebtEvidence) -> Bool {
    evidence.kind.hasPrefix("coverage.")
}

func dampenerContributions(
    _ dampeners: [AvailableDebtEvidence],
    startingValue: Double?
) -> [DebtScoreContribution] {
    var currentValue = startingValue
    return dampeners.map { availableEvidence -> DebtScoreContribution in
        let evidence = availableEvidence.evidence
        let normalizedScore = bounded(availableEvidence.normalizedScore)
        let nextValue = currentValue.map { $0 * (normalizedScore / 100) }
        let contribution = nextValue.flatMap { next in currentValue.map { next - $0 } } ?? 0
        currentValue = nextValue
        return DebtScoreContribution(
            evidenceID: evidence.id,
            kind: evidence.kind,
            rawValue: evidence.rawValue,
            normalizedScore: normalizedScore,
            configuredWeight: positiveWeight(evidence.weight),
            effectiveWeight: 0,
            contribution: contribution,
            note: dampenerNote(for: evidence)
        )
    }
}

func positiveWeight(_ weight: Double) -> Double {
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

private func dampenerNote(for evidence: DebtEvidence) -> String {
    let note = contributionNote(for: evidence)
    let dampener = "coverage dampener; cannot increase score"
    return note.map { $0 + "; " + dampener } ?? dampener
}
