import SwiftDebtCore

public enum SemanticComparisonDecision: String, Codable, Equatable, Sendable {
    case compatible
    case blocked
}

/// Immutable inputs and decision used for one directional, claim-specific
/// cross-snapshot comparison.
public struct SemanticComparisonBasis: Codable, Equatable, Sendable {
    public let claim: SemanticCompatibilityClaim
    public let decision: SemanticComparisonDecision
    public let priorSnapshotID: SnapshotID
    public let currentSnapshotID: SnapshotID
    public let priorRule: SnapshotRule
    public let currentRule: SnapshotRule
    public let priorConfigurationFingerprint: LifecycleDigest
    public let currentConfigurationFingerprint: LifecycleDigest
    public let priorCapabilities: [SnapshotCapability]
    public let currentCapabilities: [SnapshotCapability]
    public let priorSourceIdentity: SnapshotSourceIdentity
    public let currentSourceIdentity: SnapshotSourceIdentity
    public let priorScope: ObservationScope
    public let currentScope: ObservationScope
    public let priorEngineVersion: String
    public let currentEngineVersion: String
    public let compatibilityDeclaration: SemanticCompatibilityDeclaration?

    package init(
        claim: SemanticCompatibilityClaim,
        decision: SemanticComparisonDecision,
        priorSnapshot: ObservationSnapshot,
        currentSnapshot: ObservationSnapshot,
        priorRule: SnapshotRule,
        currentRule: SnapshotRule,
        compatibilityDeclaration: SemanticCompatibilityDeclaration?
    ) throws {
        self.claim = claim
        self.decision = decision
        self.priorSnapshotID = priorSnapshot.id
        self.currentSnapshotID = currentSnapshot.id
        self.priorRule = priorRule
        self.currentRule = currentRule
        self.priorConfigurationFingerprint = priorSnapshot.provenance.configurationFingerprint
        self.currentConfigurationFingerprint = currentSnapshot.provenance.configurationFingerprint
        self.priorCapabilities = priorSnapshot.provenance.capabilities
        self.currentCapabilities = currentSnapshot.provenance.capabilities
        self.priorSourceIdentity = priorSnapshot.provenance.sourceIdentity
        self.currentSourceIdentity = currentSnapshot.provenance.sourceIdentity
        self.priorScope = priorSnapshot.provenance.scope
        self.currentScope = currentSnapshot.provenance.scope
        self.priorEngineVersion = priorSnapshot.provenance.engineVersion
        self.currentEngineVersion = currentSnapshot.provenance.engineVersion
        self.compatibilityDeclaration = compatibilityDeclaration
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.claim = try values.decode(SemanticCompatibilityClaim.self, forKey: .claim)
        self.decision = try values.decode(SemanticComparisonDecision.self, forKey: .decision)
        self.priorSnapshotID = try values.decode(SnapshotID.self, forKey: .priorSnapshotID)
        self.currentSnapshotID = try values.decode(SnapshotID.self, forKey: .currentSnapshotID)
        self.priorRule = try values.decode(SnapshotRule.self, forKey: .priorRule)
        self.currentRule = try values.decode(SnapshotRule.self, forKey: .currentRule)
        self.priorConfigurationFingerprint = try values.decode(
            LifecycleDigest.self,
            forKey: .priorConfigurationFingerprint
        )
        self.currentConfigurationFingerprint = try values.decode(
            LifecycleDigest.self,
            forKey: .currentConfigurationFingerprint
        )
        self.priorCapabilities = try values.decode([SnapshotCapability].self, forKey: .priorCapabilities)
        self.currentCapabilities = try values.decode([SnapshotCapability].self, forKey: .currentCapabilities)
        self.priorSourceIdentity = try values.decode(SnapshotSourceIdentity.self, forKey: .priorSourceIdentity)
        self.currentSourceIdentity = try values.decode(SnapshotSourceIdentity.self, forKey: .currentSourceIdentity)
        self.priorScope = try values.decode(ObservationScope.self, forKey: .priorScope)
        self.currentScope = try values.decode(ObservationScope.self, forKey: .currentScope)
        self.priorEngineVersion = try values.decode(String.self, forKey: .priorEngineVersion)
        self.currentEngineVersion = try values.decode(String.self, forKey: .currentEngineVersion)
        self.compatibilityDeclaration = try values.decodeIfPresent(
            SemanticCompatibilityDeclaration.self,
            forKey: .compatibilityDeclaration
        )
        do {
            try validate()
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .decision,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    private func validate() throws {
        let matchingDeclaration = currentRule.compatibilityDeclarations.first {
            $0.fromRevision == priorRule.semanticRevision
        }
        let semanticsCompatible =
            priorRule.semanticRevision == currentRule.semanticRevision
            ? priorRule == currentRule
            : matchingDeclaration?.supportedClaims.contains(claim) == true
        let environmentCompatible =
            priorRule.identity == currentRule.identity
            && priorConfigurationFingerprint == currentConfigurationFingerprint
            && priorCapabilities == currentCapabilities
            && priorCapabilities.allSatisfy(\.state.supportsComparison)
            && priorSourceIdentity.supportsComparison
            && currentSourceIdentity.supportsComparison
            && priorEngineVersion == currentEngineVersion
        let expectedDecision: SemanticComparisonDecision =
            semanticsCompatible && environmentCompatible ? .compatible : .blocked
        guard
            compatibilityDeclaration
                == (priorRule.semanticRevision == currentRule.semanticRevision ? nil : matchingDeclaration),
            decision == expectedDecision
        else {
            throw LifecycleContractError.invalidArtifact(
                "A Semantic Comparison Basis is inconsistent with its persisted dimensions."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case claim
        case decision
        case priorSnapshotID
        case currentSnapshotID
        case priorRule
        case currentRule
        case priorConfigurationFingerprint
        case currentConfigurationFingerprint
        case priorCapabilities
        case currentCapabilities
        case priorSourceIdentity
        case currentSourceIdentity
        case priorScope
        case currentScope
        case priorEngineVersion
        case currentEngineVersion
        case compatibilityDeclaration
    }
}
