/// Validates a single decoded manifest entry and converts it into a
/// `RuleDefinition`. Catalog-wide checks (duplicate identity) live in
/// ``RuleManifestParser``; everything checkable from one entry's own fields
/// lives here (PRD FR-20).
enum RuleCatalogValidator {
    static func validate(
        entry: RuleManifestEntry
    ) throws -> RuleDefinition {
        let capabilities = try validateCapabilities(entry: entry)
        let category = try enumValue(
            RuleCategory.self, entry.category, field: "category", ruleID: entry.id)
        let scope = try enumValue(
            RuleScope.self, entry.scope, field: "scope", ruleID: entry.id)
        let mode = try enumValue(
            DetectionMode.self, entry.detectionMode, field: "detectionMode", ruleID: entry.id)
        let supportState = try enumValue(
            SupportState.self, entry.supportState, field: "supportState", ruleID: entry.id)
        let provenance = try validateProvenance(entry: entry)
        let evidenceContract = try validateEvidence(entry: entry, capabilities: capabilities)

        try validateMaturity(ruleID: entry.id, supportState: supportState, mode: mode)

        return RuleDefinition(
            identity: RuleIdentity(entry.id),
            metadata: RuleMetadata(
                title: entry.title,
                category: category,
                provenance: [provenance],
                supportState: supportState
            ),
            scope: scope,
            mode: mode,
            requirements: RuleRequirements(capabilities),
            evidenceContract: evidenceContract,
            semanticRevision: SemanticRevision(entry.semanticRevision)
        )
    }

    // MARK: - Requirements

    private static func validateCapabilities(
        entry: RuleManifestEntry
    ) throws -> Set<AnalysisCapability> {
        var capabilities: Set<AnalysisCapability> = []
        for rawValue in entry.requirements {
            guard let capability = AnalysisCapability(rawValue: rawValue) else {
                throw RuleManifestError.unknownCapability(ruleID: entry.id, value: rawValue)
            }
            capabilities.insert(capability)
        }
        return capabilities
    }

    // MARK: - Provenance

    private static func validateProvenance(
        entry: RuleManifestEntry
    ) throws -> RuleProvenance {
        guard let provenance = entry.provenance, provenance.researchItem > 0 else {
            throw RuleManifestError.missingProvenance(ruleID: entry.id)
        }
        return RuleProvenance(researchItem: provenance.researchItem, note: provenance.note)
    }

    // MARK: - Evidence shape

    private static func validateEvidence(
        entry: RuleManifestEntry, capabilities: Set<AnalysisCapability>
    ) throws -> EvidenceContract {
        let required = try convertPredicate(
            entry.evidence.required, ruleID: entry.id, capabilities: capabilities)
        let optional = try (entry.evidence.optional ?? []).map {
            predicate in
            try convertPredicate(predicate, ruleID: entry.id, capabilities: capabilities)
        }
        return EvidenceContract(required: required, optional: optional)
    }

    private static func convertPredicate(
        _ node: RuleManifestEvidencePredicate, ruleID: String,
        capabilities: Set<AnalysisCapability>
    ) throws -> EvidencePredicate {
        switch node {
        case .fact(let key, let rawKind):
            return try convertFact(
                key: key, rawKind: rawKind, ruleID: ruleID, capabilities: capabilities)
        case .all(let children):
            guard !children.isEmpty else {
                throw RuleManifestError.invalidEvidenceShape(
                    ruleID: ruleID, reason: "'all' predicate is empty")
            }
            return .all(
                try children.map {
                    child in
                    try convertPredicate(child, ruleID: ruleID, capabilities: capabilities)
                })
        case .any(let children):
            guard !children.isEmpty else {
                throw RuleManifestError.invalidEvidenceShape(
                    ruleID: ruleID, reason: "'any' predicate is empty")
            }
            return .any(
                try children.map {
                    child in
                    try convertPredicate(child, ruleID: ruleID, capabilities: capabilities)
                })
        case .not(let child):
            return .not(try convertPredicate(child, ruleID: ruleID, capabilities: capabilities))
        }
    }

    private static func convertFact(
        key: String, rawKind: String, ruleID: String, capabilities: Set<AnalysisCapability>
    ) throws -> EvidencePredicate {
        guard let kind = EvidenceFactKind(rawValue: rawKind) else {
            throw RuleManifestError.invalidEvidenceShape(
                ruleID: ruleID, reason: "fact '\(key)' has unknown kind '\(rawKind)'")
        }
        let requiredCapability = requiredCapability(for: kind)
        guard capabilities.contains(requiredCapability) else {
            let reason =
                "fact '\(key)' has kind '\(kind.rawValue)' which requires capability "
                + "'\(requiredCapability.rawValue)', not present in requirements"
            throw RuleManifestError.incompatibleEvidenceMetadata(ruleID: ruleID, reason: reason)
        }
        return .fact(EvidenceRequirement(key: key, kind: kind))
    }

    /// The `AnalysisCapability` an `EvidenceFactKind` implies must have been
    /// declared in `requirements` (a lightweight cross-check between the
    /// two vocabularies; each fact kind maps to exactly one capability).
    private static func requiredCapability(for kind: EvidenceFactKind) -> AnalysisCapability {
        switch kind {
        case .syntax: return .syntax
        case .metric: return .metrics
        case .relationship: return .references
        case .isolation: return .isolation
        case .controlFlow: return .controlFlow
        case .configuration: return .buildConfiguration
        case .history: return .gitHistory
        case .similarity: return .semanticSimilarity
        }
    }

    // MARK: - Maturity consistency

    private static func validateMaturity(
        ruleID: String, supportState: SupportState, mode: DetectionMode
    ) throws {
        if supportState == .notReliablyObservable && mode == .deterministic {
            let reason =
                "supportState 'notReliablyObservable' cannot pair with "
                + "detectionMode 'deterministic'"
            throw RuleManifestError.inconsistentMaturity(ruleID: ruleID, reason: reason)
        }
        let requiresRuntimeMode = mode != .runtimeDependent && mode != .external
        if supportState == .externalRuntimeRequired && requiresRuntimeMode {
            let reason =
                "supportState 'externalRuntimeRequired' requires detectionMode "
                + "'runtimeDependent' or 'external', found '\(mode.rawValue)'"
            throw RuleManifestError.inconsistentMaturity(ruleID: ruleID, reason: reason)
        }
    }

    // MARK: - Generic raw-value enum decoding

    private static func enumValue<E: RawRepresentable>(
        _: E.Type, _ rawValue: String, field: String, ruleID: String
    ) throws -> E where E.RawValue == String {
        guard let value = E(rawValue: rawValue) else {
            throw RuleManifestError.invalidEnumValue(ruleID: ruleID, field: field, value: rawValue)
        }
        return value
    }
}
