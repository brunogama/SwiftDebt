import SwiftDebtCore

struct ConfigurationComparisonAssessment {
    let isCompatible: Bool
    let declaration: ConfigurationCompatibilityDeclaration?
    let reasons: [LifecycleReason]
}

struct ConfigurationComparisonEvaluator {
    func assess(
        claim: SemanticCompatibilityClaim,
        priorSnapshot: ObservationSnapshot,
        priorRule: SnapshotRule,
        currentSnapshot: ObservationSnapshot,
        currentRule: SnapshotRule
    ) throws -> ConfigurationComparisonAssessment {
        try assess(
            claim: claim,
            priorConfigurationFingerprint: priorSnapshot.provenance.configurationFingerprint,
            priorEffectiveConfiguration: priorSnapshot.provenance.effectiveConfiguration,
            priorRule: priorRule,
            currentConfigurationFingerprint: currentSnapshot.provenance.configurationFingerprint,
            currentEffectiveConfiguration: currentSnapshot.provenance.effectiveConfiguration,
            currentRule: currentRule
        )
    }

    func assess(
        claim: SemanticCompatibilityClaim,
        priorConfigurationFingerprint: LifecycleDigest,
        priorEffectiveConfiguration: LifecycleEffectiveConfiguration?,
        priorRule: SnapshotRule,
        currentConfigurationFingerprint: LifecycleDigest,
        currentEffectiveConfiguration: LifecycleEffectiveConfiguration?,
        currentRule: SnapshotRule
    ) throws -> ConfigurationComparisonAssessment {
        if priorConfigurationFingerprint == currentConfigurationFingerprint {
            return ConfigurationComparisonAssessment(
                isCompatible: true,
                declaration: nil,
                reasons: []
            )
        }

        guard let prior = priorEffectiveConfiguration,
            let current = currentEffectiveConfiguration
        else {
            return try blocked(
                code: "configuration-basis-unavailable",
                message:
                    "The configuration fingerprints differ, but one or both snapshots lack typed effective dimensions."
            )
        }

        let dimensions = current.differingDimensions(from: prior)
        guard !dimensions.isEmpty else {
            return try blocked(
                code: "configuration-fingerprint-inconsistent",
                message: "Equal typed effective configurations carry different fingerprints."
            )
        }
        let revisionDeclarations = currentRule.configurationCompatibilityDeclarations.filter {
            $0.fromRevision == priorRule.semanticRevision
        }
        guard
            let declaration = revisionDeclarations.first(where: {
                $0.supportedClaims.contains(claim)
            })
        else {
            let code =
                revisionDeclarations.isEmpty
                ? "configuration-compatibility-not-declared"
                : "configuration-\(claim.rawValue)-not-declared"
            var reasons = [
                try reason(
                    code,
                    "The destination rule has no tested configuration declaration for \(claim.rawValue) "
                        + "from Semantic Revision \(priorRule.semanticRevision.rawValue). "
                        + differenceSummary(dimensions, prior: prior, current: current)
                )
            ]
            reasons += try dimensions.map { dimension in
                try reason(
                    "configuration-\(dimension.rawValue)-not-declared",
                    differenceMessage(
                        dimension,
                        prior: prior,
                        current: current,
                        suffix: "has no matching declaration"
                    )
                )
            }
            return ConfigurationComparisonAssessment(
                isCompatible: false,
                declaration: nil,
                reasons: reasons.sorted(by: lifecycleReasonOrder)
            )
        }

        let declaredDimensions = Set(declaration.conditions.map(\.dimension))
        let differingDimensions = Set(dimensions)
        guard declaredDimensions == differingDimensions else {
            var reasons: [LifecycleReason] = [
                try reason(
                    "configuration-declaration-dimensions-mismatch",
                    "The tested declaration does not cover exactly the changed effective configuration. "
                        + differenceSummary(dimensions, prior: prior, current: current)
                )
            ]
            for dimension in dimensions where !declaredDimensions.contains(dimension) {
                reasons.append(
                    try reason(
                        "configuration-\(dimension.rawValue)-not-declared",
                        differenceMessage(
                            dimension,
                            prior: prior,
                            current: current,
                            suffix: "is outside the tested declaration"
                        )
                    )
                )
            }
            for dimension in declaredDimensions where !differingDimensions.contains(dimension) {
                reasons.append(
                    try reason(
                        "configuration-declaration-dimension-not-different",
                        "The declaration requires differing dimension \(dimension.rawValue), "
                            + "but that dimension is equal."
                    )
                )
            }
            return ConfigurationComparisonAssessment(
                isCompatible: false,
                declaration: declaration,
                reasons: reasons.sorted(by: lifecycleReasonOrder)
            )
        }

        let failedConditions = declaration.conditions.filter {
            !current.satisfies($0, comparedFrom: prior)
        }
        guard failedConditions.isEmpty else {
            return ConfigurationComparisonAssessment(
                isCompatible: false,
                declaration: declaration,
                reasons: try failedConditions.map { condition in
                    try reason(
                        "configuration-compatibility-direction-blocked",
                        "Condition \(condition.rawValue) does not hold: "
                            + differenceMessage(
                                condition.dimension,
                                prior: prior,
                                current: current,
                                suffix: "changed in the unsupported direction"
                            )
                            + " " + differenceSummary(dimensions, prior: prior, current: current)
                    )
                }.sorted(by: lifecycleReasonOrder)
            )
        }

        let dimensionNames = dimensions.map(\.rawValue).joined(separator: ",")
        return ConfigurationComparisonAssessment(
            isCompatible: true,
            declaration: declaration,
            reasons: [
                try reason(
                    "configuration-compatibility-declared",
                    "The destination rule declares \(claim.rawValue) compatibility for dimensions "
                        + "\(dimensionNames) under \(declaration.conditions.map(\.rawValue).joined(separator: ",")); "
                        + "test=\(declaration.testEvidence.identifier): \(declaration.rationale) "
                        + differenceSummary(dimensions, prior: prior, current: current)
                )
            ]
        )
    }

    private func blocked(code: String, message: String) throws -> ConfigurationComparisonAssessment {
        ConfigurationComparisonAssessment(
            isCompatible: false,
            declaration: nil,
            reasons: [try reason(code, message)]
        )
    }

    private func differenceMessage(
        _ dimension: LifecycleConfigurationDimension,
        prior: LifecycleEffectiveConfiguration,
        current: LifecycleEffectiveConfiguration,
        suffix: String
    ) -> String {
        let values: String =
            switch dimension {
            case .sourceSelectionKind:
                "\(prior.sourceSelectionKind.rawValue) -> \(current.sourceSelectionKind.rawValue)"
            case .excludedSourcePrefixes:
                "\(render(prior.excludedSourcePrefixes)) -> "
                    + render(current.excludedSourcePrefixes)
            case .maximumFileBytes:
                "\(prior.maximumFileBytes) -> \(current.maximumFileBytes)"
            case .selectedRuleIdentities:
                "\(render(prior.selectedRuleIdentities.map(\.description))) -> "
                    + render(current.selectedRuleIdentities.map(\.description))
            }
        return "Effective configuration dimension \(dimension.rawValue) changed \(values) and \(suffix)."
    }

    private func render(_ values: [String]) -> String {
        "[\(values.joined(separator: ","))]"
    }

    private func differenceSummary(
        _ dimensions: [LifecycleConfigurationDimension],
        prior: LifecycleEffectiveConfiguration,
        current: LifecycleEffectiveConfiguration
    ) -> String {
        let values = dimensions.map {
            differenceMessage($0, prior: prior, current: current, suffix: "was compared")
        }
        return "Differing dimensions: \(values.joined(separator: " "))"
    }

    private func reason(_ code: String, _ message: String) throws -> LifecycleReason {
        try LifecycleReason(code: code, message: message)
    }
}
