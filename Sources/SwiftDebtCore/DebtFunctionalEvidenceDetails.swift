extension DebtFunctionalEvidenceBuilder {
    func functionEvidence(for function: FunctionFacts, module: String) -> [DebtEvidence] {
        let location = DebtLocation(module: module, source: function.location)
        var result = effectEvidence(for: function, location: location)
        if let composition = compositionEvidence(for: function, location: location) {
            result.append(composition)
        }
        if options.includesSwiftSpecificRiskEvidence {
            result.append(
                contentsOf: groupedRiskEvidence(
                    facts: function.riskFacts, idPrefix: function.name, locationModule: module))
            result.append(contentsOf: apiRiskEvidence(for: function, module: module))
        }
        result.append(patternConsistencyEvidence(for: function, location: location))
        return result.sorted { $0.id < $1.id }
    }

    private func effectEvidence(
        for function: FunctionFacts, location: DebtLocation
    ) -> [DebtEvidence] {
        let grouped = Dictionary(grouping: function.effectFacts, by: \.category)
        let measured = SyntaxEffectCategory.allCases.compactMap { category in
            grouped[category].flatMap {
                effectEvidence(for: category, facts: $0, function: function, location: location)
            }
        }
        guard measured.isEmpty else { return measured }
        return [
            DebtEvidence(
                id: "\(function.name):purity:heuristic", kind: "swift.purity.heuristic",
                weight: 1, normalizedScore: 0, rawValue: "measuredSyntaxEffects=0",
                location: location,
                note:
                    "Heuristic inference from absence of recognized SwiftSyntax effect markers; "
                    + "not compiler semantic proof."
            )
        ]
    }

    private func effectEvidence(
        for category: SyntaxEffectCategory,
        facts: [SyntaxEffectFact],
        function: FunctionFacts,
        location: DebtLocation
    ) -> DebtEvidence? {
        guard !facts.isEmpty else { return nil }
        let ordered = facts.sorted(by: functionalEffectOrder)
        return DebtEvidence(
            id: "\(function.name):effect:\(category.rawValue)",
            kind: "swift.side-effect.\(category.rawValue)",
            weight: weight(for: category),
            normalizedScore: score(for: category, count: ordered.count),
            rawValue:
                "count=\(ordered.count);details=\(ordered.map(\.detail).joined(separator: ","))",
            location: location,
            note:
                "Measured SwiftSyntax facts with \(confidenceSummary(ordered.map(\.confidence))) confidence; not compiler semantic proof."
        )
    }

    private func compositionEvidence(
        for function: FunctionFacts, location: DebtLocation
    ) -> DebtEvidence? {
        guard !function.compositionFacts.isEmpty else { return nil }
        let ordered = function.compositionFacts.sorted(by: functionalCompositionOrder)
        let impureClosures = ordered.filter(\.closureHasSideEffects).count
        return DebtEvidence(
            id: "\(function.name):functional-composition",
            kind: "swift.functional-composition", weight: 0.5,
            normalizedScore: Double(impureClosures * 15),
            rawValue:
                "operations=\(ordered.map(\.operation).joined(separator: ","));impureClosures=\(impureClosures)",
            location: location,
            note:
                "Measured functional call syntax; benign pure closures reduce false positives, "
                + "but not compiler semantic proof."
        )
    }

    private func patternConsistencyEvidence(
        for function: FunctionFacts, location: DebtLocation
    ) -> DebtEvidence {
        let inputs = [
            "locf=\(function.codeLines)", "ccf=\(function.complexity)",
            "parameters=\(function.parameters)",
            "effectKinds=\(Set(function.effectFacts.map(\.category)).count)",
            "composition=\(function.compositionFacts.count)",
        ]
        return DebtEvidence(
            id: "\(function.name):pattern-consistency",
            kind: "swift.pattern-consistency.heuristic", weight: 0.75,
            normalizedScore: patternScore(function), rawValue: inputs.joined(separator: ";"),
            location: location,
            note:
                "Heuristic pattern-consistency score from deterministic syntax counts; not "
                + "compiler semantic proof."
        )
    }

    func groupedRiskEvidence(
        facts: [SwiftRiskFact],
        idPrefix: String,
        locationModule: String
    ) -> [DebtEvidence] {
        let grouped = Dictionary(grouping: facts, by: \.category)
        return SwiftRiskCategory.allCases.compactMap { category in
            guard let facts = grouped[category], !facts.isEmpty else { return nil }
            let ordered = facts.sorted(by: functionalRiskOrder)
            return DebtEvidence(
                id: "\(idPrefix):swift-risk:\(category.rawValue)",
                kind: riskKind(for: category),
                weight: riskWeight(for: category),
                normalizedScore: riskScore(for: category, count: ordered.count),
                rawValue:
                    "count=\(ordered.count);details=\(ordered.map(\.detail).joined(separator: ","))",
                location: DebtLocation(module: locationModule, source: ordered[0].location),
                note:
                    "Heuristic SwiftSyntax risk evidence with \(confidenceSummary(ordered.map(\.confidence))) confidence; not compiler semantic proof."
            )
        }
    }

    func apiRiskEvidence(for function: FunctionFacts, module: String) -> [DebtEvidence] {
        let location = DebtLocation(module: module, source: function.location)
        return [
            parameterRiskEvidence(for: function, location: location),
            boundaryRiskEvidence(for: function, location: location),
        ].compactMap { $0 }
    }

    private func parameterRiskEvidence(
        for function: FunctionFacts, location: DebtLocation
    ) -> DebtEvidence? {
        guard function.parameters >= 6 else { return nil }
        return DebtEvidence(
            id: "\(function.name):api-risk:parameter-surface",
            kind: "swift.api-risk.parameter-surface", weight: 1.25,
            normalizedScore: Double(min(100, (function.parameters - 5) * 20)),
            rawValue: "parameters=\(function.parameters)", location: location,
            note: "Heuristic API surface risk from SwiftSyntax parameter count; not "
                + "compiler semantic proof.")
    }

    private func boundaryRiskEvidence(
        for function: FunctionFacts, location: DebtLocation
    ) -> DebtEvidence? {
        guard let accessLevel = function.accessLevel,
            ["open", "public", "package"].contains(accessLevel)
        else { return nil }
        let raw =
            function.complexity * 8 + function.parameters * 6
            + max(0, function.codeLines - 12) * 2
        guard raw >= 40 else { return nil }
        return DebtEvidence(
            id: "\(function.name):api-risk:public-boundary-complexity",
            kind: "swift.api-risk.public-boundary-complexity", weight: 1.5,
            normalizedScore: Double(min(100, raw)),
            rawValue: "access=\(accessLevel);ccf=\(function.complexity);parameters="
                + "\(function.parameters);locf=\(function.codeLines)",
            location: location,
            note: "Heuristic public-boundary complexity from SwiftSyntax counts; not "
                + "compiler semantic proof.")
    }

}

private func functionalEffectOrder(_ lhs: SyntaxEffectFact, _ rhs: SyntaxEffectFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.detail != rhs.detail { return lhs.detail < rhs.detail }
    if lhs.confidence != rhs.confidence { return lhs.confidence.rawValue < rhs.confidence.rawValue }
    return false
}

private func functionalCompositionOrder(
    _ lhs: FunctionalCompositionFact, _ rhs: FunctionalCompositionFact
) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.operation != rhs.operation { return lhs.operation < rhs.operation }
    if lhs.closureHasSideEffects != rhs.closureHasSideEffects { return !lhs.closureHasSideEffects }
    return lhs.confidence.rawValue < rhs.confidence.rawValue
}

private func functionalRiskOrder(_ lhs: SwiftRiskFact, _ rhs: SwiftRiskFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.detail != rhs.detail { return lhs.detail < rhs.detail }
    return lhs.confidence.rawValue < rhs.confidence.rawValue
}
