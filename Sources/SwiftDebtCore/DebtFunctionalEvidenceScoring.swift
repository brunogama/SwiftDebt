extension DebtFunctionalEvidenceBuilder {
    private static let riskWeights: [SwiftRiskCategory: Double] = [
        .isolationCrossing: 1.25,
        .actorIsolation: 0.75,
        .globalActorIsolation: 1,
        .sendableConformance: 0.75,
        .uncheckedSendable: 2,
        .unstructuredTask: 1.75,
        .nonisolatedDeclaration: 1.5,
        .mutableSharedState: 2,
        .unsafeEscapeHatch: 2,
        .errorSwallowing: 1.75,
        .errorTermination: 2,
        .testSynchronization: 1.5,
    ]

    func patternScore(_ function: FunctionFacts) -> Double {
        let effectKinds = Set(function.effectFacts.map(\.category)).count
        let raw =
            function.complexity * 6 + function.parameters * 4 + effectKinds * 10 + max(
                0, function.codeLines - 8) * 3
        return Double(min(100, raw))
    }

    func score(for category: SyntaxEffectCategory, count: Int) -> Double {
        min(100, Double(count) * weight(for: category) * 12)
    }

    func weight(for category: SyntaxEffectCategory) -> Double {
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

    func riskKind(for category: SwiftRiskCategory) -> String {
        switch category {
        case .mutableSharedState:
            return "swift.shared-state.mutable"
        case .errorSwallowing:
            return "swift.error-handling.swallowing"
        case .errorTermination:
            return "swift.error-handling.termination"
        case .testSynchronization:
            return "swift.testing.synchronization"
        default:
            return "swift.concurrency-risk.\(category.rawValue)"
        }
    }

    func riskScore(for category: SwiftRiskCategory, count: Int) -> Double {
        min(100, Double(count) * riskWeight(for: category) * 15)
    }

    func riskWeight(for category: SwiftRiskCategory) -> Double {
        Self.riskWeights[category, default: 1]
    }

    func confidenceSummary(_ values: [SyntaxEvidenceConfidence]) -> String {
        let rawValues = Set(values.map(\.rawValue)).sorted()
        return rawValues.joined(separator: "+")
    }
}
