/// A build-time (or tool-time) failure while parsing or validating a Rule
/// Catalog Manifest (addendum H, ADR 0001 Q9/Q12 - compile-time half of the
/// two validation passes). Every case names the offending manifest entry so
/// a failure is actionable without re-reading the whole catalog file.
public enum RuleManifestError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The same `RuleIdentity` appears on more than one manifest entry.
    case duplicateIdentity(id: String)

    /// A `requirements` entry is not one of `AnalysisCapability`'s raw values.
    case unknownCapability(ruleID: String, value: String)

    /// `category`, `scope`, `detectionMode`, or `supportState` is not a valid
    /// raw value of its corresponding enum.
    case invalidEnumValue(ruleID: String, field: String, value: String)

    /// An `all`/`any` predicate node has no children, or a `fact` node names
    /// a `kind` that is not a valid `EvidenceFactKind` raw value.
    case invalidEvidenceShape(ruleID: String, reason: String)

    /// The `provenance` block is missing, or names a non-positive research item.
    case missingProvenance(ruleID: String)

    /// `supportState` and `detectionMode` make claims that cannot both be
    /// true at once (e.g. `.notReliablyObservable` paired with
    /// `.deterministic`, or `.externalRuntimeRequired` without a
    /// runtime/external detection mode).
    case inconsistentMaturity(ruleID: String, reason: String)

    /// An evidence fact's `kind` names an `EvidenceFactKind` that has no
    /// corresponding capability declared in `requirements`.
    case incompatibleEvidenceMetadata(ruleID: String, reason: String)

    /// The manifest text itself could not be decoded as YAML/structured data.
    case malformedDocument(reason: String)

    public var description: String {
        switch self {
        case .duplicateIdentity(let id):
            return "rule catalog manifest error: duplicate rule identity '\(id)'"
        case .unknownCapability(let ruleID, let value):
            return
                "rule catalog manifest error: rule '\(ruleID)' declares unknown capability requirement '\(value)'"
        case .invalidEnumValue(let ruleID, let field, let value):
            return
                "rule catalog manifest error: rule '\(ruleID)' has invalid \(field) value '\(value)'"
        case .invalidEvidenceShape(let ruleID, let reason):
            return "rule catalog manifest error: rule '\(ruleID)' has an invalid evidence shape: \(reason)"
        case .missingProvenance(let ruleID):
            return
                "rule catalog manifest error: rule '\(ruleID)' is missing a valid provenance (researchItem must be a positive integer)"
        case .inconsistentMaturity(let ruleID, let reason):
            return "rule catalog manifest error: rule '\(ruleID)' has inconsistent maturity metadata: \(reason)"
        case .incompatibleEvidenceMetadata(let ruleID, let reason):
            return
                "rule catalog manifest error: rule '\(ruleID)' has incompatible evidence metadata: \(reason)"
        case .malformedDocument(let reason):
            return "rule catalog manifest error: malformed manifest document: \(reason)"
        }
    }
}
