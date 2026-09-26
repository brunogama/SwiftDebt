import SwiftDebtCore

struct SemanticComparisonAssessment {
    let basis: SemanticComparisonBasis
    let reasons: [LifecycleReason]

    var isCompatible: Bool { basis.decision == .compatible }
}

struct SemanticComparisonEvaluator {
    func assess(
        claim: SemanticCompatibilityClaim,
        priorSnapshot: ObservationSnapshot,
        priorRule: SnapshotRule,
        currentSnapshot: ObservationSnapshot,
        currentRule: SnapshotRule
    ) throws -> SemanticComparisonAssessment {
        let declaration = matchingDeclaration(
            priorRule: priorRule,
            currentRule: currentRule
        )
        var reasons = try environmentReasons(
            claim: claim,
            priorSnapshot: priorSnapshot,
            priorRule: priorRule,
            currentSnapshot: currentSnapshot,
            currentRule: currentRule
        )
        reasons += try semanticReasons(
            claim: claim,
            priorRule: priorRule,
            currentRule: currentRule,
            declaration: declaration
        )

        let blockingCodes = Set([
            "rule-identity-incomparable",
            "configuration-incomparable",
            "engine-incomparable",
            "source-identity-unavailable",
            "capability-incomparable",
            "capabilities-incomparable",
            "capability-unavailable",
            "semantic-continuity-not-declared",
            "semantic-absence-not-declared",
            "semantic-revision-incomparable",
            "semantic-contract-mutated",
        ])
        let decision: SemanticComparisonDecision =
            reasons.contains(where: { blockingCodes.contains($0.code) }) ? .blocked : .compatible
        let basis = try SemanticComparisonBasis(
            claim: claim,
            decision: decision,
            priorSnapshot: priorSnapshot,
            currentSnapshot: currentSnapshot,
            priorRule: priorRule,
            currentRule: currentRule,
            compatibilityDeclaration: declaration
        )
        return SemanticComparisonAssessment(
            basis: basis,
            reasons: reasons.sorted(by: lifecycleReasonOrder)
        )
    }

    private func matchingDeclaration(
        priorRule: SnapshotRule,
        currentRule: SnapshotRule
    ) -> SemanticCompatibilityDeclaration? {
        guard priorRule.semanticRevision != currentRule.semanticRevision else { return nil }
        return currentRule.compatibilityDeclarations.first {
            $0.fromRevision == priorRule.semanticRevision
        }
    }

    private func environmentReasons(
        claim: SemanticCompatibilityClaim,
        priorSnapshot: ObservationSnapshot,
        priorRule: SnapshotRule,
        currentSnapshot: ObservationSnapshot,
        currentRule: SnapshotRule
    ) throws -> [LifecycleReason] {
        var reasons: [LifecycleReason] = []
        if priorRule.identity != currentRule.identity {
            reasons.append(try reason("rule-identity-incomparable", "Semantic comparison requires one Rule Identity."))
        }
        if priorSnapshot.provenance.configurationFingerprint
            != currentSnapshot.provenance.configurationFingerprint
        {
            reasons.append(
                try reason(
                    "configuration-incomparable",
                    "The current and prior effective configuration fingerprints differ."
                )
            )
        }
        if priorSnapshot.provenance.engineVersion != currentSnapshot.provenance.engineVersion {
            reasons.append(
                try reason(
                    "engine-incomparable",
                    "The analysis engine version changed without a compatibility declaration."
                )
            )
        }
        if !priorSnapshot.provenance.sourceIdentity.supportsComparison
            || !currentSnapshot.provenance.sourceIdentity.supportsComparison
        {
            reasons.append(
                try reason(
                    "source-identity-unavailable",
                    "Comparable source identity is unavailable for one or both snapshots."
                )
            )
        }
        if priorSnapshot.provenance.capabilities != currentSnapshot.provenance.capabilities {
            reasons.append(
                try reason(
                    claim == .continuity ? "capability-incomparable" : "capabilities-incomparable",
                    "Capability availability changed: prior ["
                        + capabilitySummary(priorSnapshot.provenance.capabilities)
                        + "]; current ["
                        + capabilitySummary(currentSnapshot.provenance.capabilities) + "]."
                )
            )
        }
        if priorSnapshot.provenance.capabilities.contains(where: { !$0.state.supportsComparison })
            || currentSnapshot.provenance.capabilities.contains(where: { !$0.state.supportsComparison })
        {
            reasons.append(
                try reason(
                    claim == .continuity ? "capability-incomparable" : "capability-unavailable",
                    "Required capabilities are unavailable or ambiguous: prior ["
                        + capabilitySummary(priorSnapshot.provenance.capabilities)
                        + "]; current ["
                        + capabilitySummary(currentSnapshot.provenance.capabilities) + "]."
                )
            )
        }
        return reasons
    }

    private func capabilitySummary(_ capabilities: [SnapshotCapability]) -> String {
        guard !capabilities.isEmpty else { return "none" }
        return capabilities.map { capability in
            let state: String
            switch capability.state {
            case .available:
                state = "available"
            case .unavailable(let reason):
                state = "unavailable (\(reason.code): \(reason.message))"
            case .ambiguous(let reason):
                state = "ambiguous (\(reason.code): \(reason.message))"
            }
            return "\(capability.name)=\(state)"
        }.joined(separator: ", ")
    }

    private func semanticReasons(
        claim: SemanticCompatibilityClaim,
        priorRule: SnapshotRule,
        currentRule: SnapshotRule,
        declaration: SemanticCompatibilityDeclaration?
    ) throws -> [LifecycleReason] {
        if priorRule.semanticRevision == currentRule.semanticRevision {
            guard priorRule != currentRule else { return [] }
            return [
                try reason(
                    "semantic-contract-mutated",
                    "The same Semantic Revision carries different persisted compatibility declarations."
                )
            ]
        }
        guard let declaration else {
            return [
                try reason(
                    "semantic-revision-incomparable",
                    "The current and prior Semantic Revisions have no compatible directional declaration."
                )
            ]
        }
        guard declaration.supportedClaims.contains(claim) else {
            return [
                try reason(
                    "semantic-\(claim.rawValue)-not-declared",
                    "The destination rule's cross-revision declaration does not authorize \(claim.rawValue)."
                )
            ]
        }
        return [
            try reason(
                "semantic-compatibility-declared",
                "The destination rule declares \(claim.rawValue) compatibility from Semantic Revision "
                    + "\(priorRule.semanticRevision.rawValue) to "
                    + "\(currentRule.semanticRevision.rawValue): \(declaration.rationale)"
            )
        ]
    }

    private func reason(_ code: String, _ message: String) throws -> LifecycleReason {
        try LifecycleReason(code: code, message: message)
    }
}

func semanticComparisonOrder(_ lhs: SemanticComparisonBasis, _ rhs: SemanticComparisonBasis) -> Bool {
    if lhs.priorSnapshotID != rhs.priorSnapshotID {
        return lhs.priorSnapshotID.rawValue < rhs.priorSnapshotID.rawValue
    }
    if lhs.currentSnapshotID != rhs.currentSnapshotID {
        return lhs.currentSnapshotID.rawValue < rhs.currentSnapshotID.rawValue
    }
    if lhs.priorRule.identity != rhs.priorRule.identity {
        return lhs.priorRule.identity.description < rhs.priorRule.identity.description
    }
    return lhs.claim.rawValue < rhs.claim.rawValue
}

func uniqueSemanticComparisons(_ values: [SemanticComparisonBasis]) -> [SemanticComparisonBasis] {
    values.reduce(into: [SemanticComparisonBasis]()) { result, value in
        if !result.contains(value) { result.append(value) }
    }.sorted(by: semanticComparisonOrder)
}
