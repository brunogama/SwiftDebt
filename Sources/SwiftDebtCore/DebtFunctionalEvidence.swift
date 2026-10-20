package struct DebtFunctionalEvidenceOptions: Sendable {
    package let includesSwiftSpecificRiskEvidence: Bool

    package init(includesSwiftSpecificRiskEvidence: Bool = true) {
        self.includesSwiftSpecificRiskEvidence = includesSwiftSpecificRiskEvidence
    }
}

package struct DebtFunctionalEvidenceBuilder: Sendable {
    package let options: DebtFunctionalEvidenceOptions

    package init(options: DebtFunctionalEvidenceOptions = DebtFunctionalEvidenceOptions()) {
        self.options = options
    }

    package func evidence(for sources: [ParsedSource]) -> [DebtEvidence] {
        sources
            .filter(\.isValid)
            .flatMap { source in evidence(for: source) }
            .sorted(by: evidenceOrder)
    }

    private func evidence(for source: ParsedSource) -> [DebtEvidence] {
        let callableEvidence = source.functions
            .sorted { lhs, rhs in
                if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
                return lhs.name < rhs.name
            }
            .flatMap { functionEvidence(for: $0, module: source.module) }
        guard options.includesSwiftSpecificRiskEvidence else { return callableEvidence }
        return (sourceRiskEvidence(for: source) + callableEvidence).sorted(by: evidenceOrder)
    }

    private func sourceRiskEvidence(for source: ParsedSource) -> [DebtEvidence] {
        groupedRiskEvidence(
            facts: source.riskFacts,
            idPrefix: "\(source.module).\(source.path)",
            locationModule: source.module
        )
    }

}

private func evidenceOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    if lhs.rawValue != rhs.rawValue { return lhs.rawValue < rhs.rawValue }
    return String(reflecting: lhs.note) < String(reflecting: rhs.note)
}
