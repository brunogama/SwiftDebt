package struct ScoreInputs {
    package let methodCount: Int
    package let propertyCount: Int
    package let parameterCount: Int
    package let duplicateLines: Int
    package let totalLines: Int
}

package struct PaperScoring {
    package func score(
        metric: Metric, values: [Int], inputs: ScoreInputs, mode: ScoringMode
    ) -> (value: Double?, note: String?) {
        guard mode != .none else {
            return (nil, "Scoring disabled; raw metrics and thresholds remain available.")
        }
        if metric != .dc && values.isEmpty { return (nil, "No applicable entities.") }
        let value = rawScore(metric: metric, values: values, inputs: inputs, mode: mode)
        guard let raw = value, raw.isFinite else {
            return (
                nil,
                "Table I is undefined for these inputs (zero denominator); no replacement score "
                    + "is invented."
            )
        }
        if mode == .bounded || mode == .corrected {
            let note =
                mode == .corrected && metric == .dc
                ? "DC ratio uses duplicatedLines / totalLines (documented repair), then a 0...5 "
                    + "clamp."
                : "Table I followed by an explicit 0...5 clamp; this does not validate or repair "
                    + "the model."
            return (min(5, max(0, raw)), note)
        }
        return (
            raw, raw > 5 ? "Literal Table I result exceeds the paper's stated 0...5 range." : nil
        )
    }

    private func rawScore(
        metric: Metric, values: [Int], inputs: ScoreInputs, mode: ScoringMode
    ) -> Double? {
        let maximum = Double(values.max() ?? 0)
        switch metric {
        case .locc:
            return 1000 / (maximum + 1500)
        case .nomc, .nogc:
            return 500 / (maximum + 75)
        case .nocc:
            return 1000 / (maximum + 150)
        case .locf:
            return 2000 / (maximum + 300)
        case .wmcc, .ccf, .nopf:
            return violationScore(metric: metric, values: values, maximum: maximum)
        case .noav:
            guard inputs.propertyCount > 0 else { return nil }
            return 2 / (Double(inputs.methodCount) / Double(inputs.propertyCount) + 0.4)
        case .dc:
            return duplicationScore(inputs: inputs, mode: mode)
        }
    }

    private func violationScore(metric: Metric, values: [Int], maximum: Double) -> Double? {
        let total = values.reduce(0.0) { $0 + Double($1) }
        let violations = Double(values.filter { $0 > metric.paperThreshold! }.count)
        if violations == 0 { return 2 / 0.4 }
        guard total > 0 else { return nil }
        return 2 / ((maximum * violations / total) + 0.4)
    }

    private func duplicationScore(inputs: ScoreInputs, mode: ScoringMode) -> Double? {
        if inputs.duplicateLines == 0 { return 2 / 0.4 }
        if mode == .corrected {
            guard inputs.totalLines > 0 else { return nil }
            return 2 / (Double(inputs.duplicateLines) / Double(inputs.totalLines) + 0.4)
        }
        guard inputs.parameterCount > 0 else { return nil }
        let ratio =
            Double(inputs.duplicateLines) * Double(inputs.totalLines)
            / Double(inputs.parameterCount)
        return 2 / (ratio + 0.4)
    }
}
