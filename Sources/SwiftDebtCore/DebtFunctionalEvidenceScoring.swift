extension DebtFunctionalEvidenceBuilder {
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
        switch category {
        case .isolationCrossing: 1.25
        case .actorIsolation, .sendableConformance: 0.75
        case .globalActorIsolation: 1
        case .uncheckedSendable, .mutableSharedState, .unsafeEscapeHatch, .errorTermination: 2
        case .unstructuredTask, .errorSwallowing: 1.75
        case .nonisolatedDeclaration: 1.5
        case .testSynchronization: 1.5
        }
    }

    func confidenceSummary(_ values: [SyntaxEvidenceConfidence]) -> String {
        let rawValues = Set(values.map(\.rawValue)).sorted()
        return rawValues.joined(separator: "+")
    }
}
