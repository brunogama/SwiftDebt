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

    private func functionEvidence(for function: FunctionFacts, module: String) -> [DebtEvidence] {
        var result: [DebtEvidence] = []
        let location = DebtLocation(module: module, source: function.location)
        let groupedEffects = Dictionary(grouping: function.effectFacts, by: \.category)
        for category in SyntaxEffectCategory.allCases {
            guard let facts = groupedEffects[category], !facts.isEmpty else { continue }
            let ordered = facts.sorted(by: effectOrder)
            result.append(
                DebtEvidence(
                    id: "\(function.name):effect:\(category.rawValue)",
                    kind: "swift.side-effect.\(category.rawValue)",
                    weight: weight(for: category),
                    normalizedScore: score(for: category, count: ordered.count),
                    rawValue: "count=\(ordered.count);details=\(ordered.map(\.detail).joined(separator: ","))",
                    location: location,
                    note:
                        "Measured SwiftSyntax facts with \(confidenceSummary(ordered.map(\.confidence))) confidence; not compiler semantic proof."
                )
            )
        }
        if function.effectFacts.isEmpty {
            result.append(
                DebtEvidence(
                    id: "\(function.name):purity:heuristic",
                    kind: "swift.purity.heuristic",
                    weight: 1,
                    normalizedScore: 0,
                    rawValue: "measuredSyntaxEffects=0",
                    location: location,
                    note:
                        "Heuristic inference from absence of recognized SwiftSyntax effect markers; not compiler semantic proof."
                )
            )
        }
        if !function.compositionFacts.isEmpty {
            let ordered = function.compositionFacts.sorted(by: compositionOrder)
            let impureClosures = ordered.filter(\.closureHasSideEffects).count
            result.append(
                DebtEvidence(
                    id: "\(function.name):functional-composition",
                    kind: "swift.functional-composition",
                    weight: 0.5,
                    normalizedScore: Double(impureClosures * 15),
                    rawValue:
                        "operations=\(ordered.map(\.operation).joined(separator: ","));impureClosures=\(impureClosures)",
                    location: location,
                    note:
                        "Measured functional call syntax; benign pure closures reduce false positives, but not compiler semantic proof."
                )
            )
        }
        if options.includesSwiftSpecificRiskEvidence {
            result.append(
                contentsOf: groupedRiskEvidence(
                    facts: function.riskFacts, idPrefix: function.name, locationModule: module))
            result.append(contentsOf: apiRiskEvidence(for: function, module: module))
        }
        let entropyInputs = [
            "locf=\(function.codeLines)",
            "ccf=\(function.complexity)",
            "parameters=\(function.parameters)",
            "effectKinds=\(Set(function.effectFacts.map(\.category)).count)",
            "composition=\(function.compositionFacts.count)",
        ]
        result.append(
            DebtEvidence(
                id: "\(function.name):pattern-consistency",
                kind: "swift.pattern-consistency.heuristic",
                weight: 0.75,
                normalizedScore: patternScore(function),
                rawValue: entropyInputs.joined(separator: ";"),
                location: location,
                note:
                    "Heuristic pattern-consistency score from deterministic syntax counts; not compiler semantic proof."
            )
        )
        return result.sorted(by: evidenceOrder)
    }

    private func groupedRiskEvidence(
        facts: [SwiftRiskFact],
        idPrefix: String,
        locationModule: String
    ) -> [DebtEvidence] {
        let grouped = Dictionary(grouping: facts, by: \.category)
        return SwiftRiskCategory.allCases.compactMap { category in
            guard let facts = grouped[category], !facts.isEmpty else { return nil }
            let ordered = facts.sorted(by: riskOrder)
            return DebtEvidence(
                id: "\(idPrefix):swift-risk:\(category.rawValue)",
                kind: riskKind(for: category),
                weight: riskWeight(for: category),
                normalizedScore: riskScore(for: category, count: ordered.count),
                rawValue: "count=\(ordered.count);details=\(ordered.map(\.detail).joined(separator: ","))",
                location: DebtLocation(module: locationModule, source: ordered[0].location),
                note:
                    "Heuristic SwiftSyntax risk evidence with \(confidenceSummary(ordered.map(\.confidence))) confidence; not compiler semantic proof."
            )
        }
    }

    private func apiRiskEvidence(for function: FunctionFacts, module: String) -> [DebtEvidence] {
        var result: [DebtEvidence] = []
        let location = DebtLocation(module: module, source: function.location)
        if function.parameters >= 6 {
            result.append(
                DebtEvidence(
                    id: "\(function.name):api-risk:parameter-surface",
                    kind: "swift.api-risk.parameter-surface",
                    weight: 1.25,
                    normalizedScore: Double(min(100, (function.parameters - 5) * 20)),
                    rawValue: "parameters=\(function.parameters)",
                    location: location,
                    note: "Heuristic API surface risk from SwiftSyntax parameter count; not compiler semantic proof."
                )
            )
        }
        if let accessLevel = function.accessLevel, ["open", "public", "package"].contains(accessLevel) {
            let raw = function.complexity * 8 + function.parameters * 6 + max(0, function.codeLines - 12) * 2
            if raw >= 40 {
                result.append(
                    DebtEvidence(
                        id: "\(function.name):api-risk:public-boundary-complexity",
                        kind: "swift.api-risk.public-boundary-complexity",
                        weight: 1.5,
                        normalizedScore: Double(min(100, raw)),
                        rawValue:
                            "access=\(accessLevel);ccf=\(function.complexity);parameters=\(function.parameters);locf=\(function.codeLines)",
                        location: location,
                        note:
                            "Heuristic public-boundary complexity from SwiftSyntax counts; not compiler semantic proof."
                    )
                )
            }
        }
        return result
    }

    private func patternScore(_ function: FunctionFacts) -> Double {
        let effectKinds = Set(function.effectFacts.map(\.category)).count
        let raw =
            function.complexity * 6 + function.parameters * 4 + effectKinds * 10 + max(0, function.codeLines - 8) * 3
        return Double(min(100, raw))
    }

    private func score(for category: SyntaxEffectCategory, count: Int) -> Double {
        min(100, Double(count) * weight(for: category) * 12)
    }

    private func weight(for category: SyntaxEffectCategory) -> Double {
        switch category {
        case .mutation: 1
        case .inoutMutation: 1.25
        case .propertyWrite: 1.5
        case .globalOrStaticState: 2
        case .asyncEffect: 1
        case .throwingEffect: 1
        case .closureEffect: 1.25
        }
    }

    private func riskKind(for category: SwiftRiskCategory) -> String {
        switch category {
        case .mutableSharedState:
            return "swift.shared-state.mutable"
        default:
            return "swift.concurrency-risk.\(category.rawValue)"
        }
    }

    private func riskScore(for category: SwiftRiskCategory, count: Int) -> Double {
        min(100, Double(count) * riskWeight(for: category) * 15)
    }

    private func riskWeight(for category: SwiftRiskCategory) -> Double {
        switch category {
        case .isolationCrossing: 1.25
        case .actorIsolation: 0.75
        case .globalActorIsolation: 1
        case .sendableConformance: 0.75
        case .uncheckedSendable: 2
        case .unstructuredTask: 1.75
        case .nonisolatedDeclaration: 1.5
        case .mutableSharedState: 2
        case .unsafeEscapeHatch: 2
        }
    }

    private func confidenceSummary(_ values: [SyntaxEvidenceConfidence]) -> String {
        let rawValues = Set(values.map(\.rawValue)).sorted()
        return rawValues.joined(separator: "+")
    }
}

private func evidenceOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    if lhs.rawValue != rhs.rawValue { return lhs.rawValue < rhs.rawValue }
    return String(reflecting: lhs.note) < String(reflecting: rhs.note)
}

private func effectOrder(_ lhs: SyntaxEffectFact, _ rhs: SyntaxEffectFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.detail != rhs.detail { return lhs.detail < rhs.detail }
    if lhs.confidence != rhs.confidence { return lhs.confidence.rawValue < rhs.confidence.rawValue }
    return false
}

private func compositionOrder(_ lhs: FunctionalCompositionFact, _ rhs: FunctionalCompositionFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.operation != rhs.operation { return lhs.operation < rhs.operation }
    if lhs.closureHasSideEffects != rhs.closureHasSideEffects { return !lhs.closureHasSideEffects }
    return lhs.confidence.rawValue < rhs.confidence.rawValue
}

private func riskOrder(_ lhs: SwiftRiskFact, _ rhs: SwiftRiskFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.detail != rhs.detail { return lhs.detail < rhs.detail }
    return lhs.confidence.rawValue < rhs.confidence.rawValue
}
