/// Names a required *kind* of evidence without carrying its observed value.
/// The contract states what must be available; `EvidenceFact` (below) carries
/// what was actually observed for a given Detection.
public struct EvidenceRequirement: Codable, Hashable, Sendable {
    public let key: String
    public let kind: EvidenceFactKind

    public init(key: String, kind: EvidenceFactKind) {
        self.key = key
        self.kind = kind
    }
}

/// Boolean algebra over evidence requirements (addendum E). Expresses
/// alternative valid evidence paths (e.g. blocking-semaphore-in-async needs
/// the wait call AND (async context OR MainActor context)) without a generic
/// expression language - the catalog declares the shape, Swift implements
/// the algorithm (addendum E explicit constraint).
public indirect enum EvidencePredicate: Codable, Hashable, Sendable {
    case fact(EvidenceRequirement)
    case all([Self])
    case any([Self])
    case not(Self)
}

/// Required/optional evidence for evaluating a rule (PRD FR-7). Unavailable
/// required evidence prevents complete evaluation - it degrades
/// `ObservationState`, it never becomes a `.complete` "clean" result
/// (Invariant Q3).
public struct EvidenceContract: Codable, Hashable, Sendable {
    public let required: EvidencePredicate
    public let optional: [EvidencePredicate]

    public init(required: EvidencePredicate, optional: [EvidencePredicate] = []) {
        self.required = required
        self.optional = optional
    }
}

/// Coarse classification of an evidence fact's origin (addendum F). This is
/// the contract-level vocabulary only; the fully typed payload for each kind
/// (`SyntaxEvidence`, `IsolationEvidence`, etc.) is deliberately deferred to
/// the sensor/evidence-facts unit downstream of this pilot - inventing those
/// payload shapes now, before a sensor exists to populate them, would be
/// speculative.
public enum EvidenceFactKind: String, Codable, CaseIterable, Sendable {
    case syntax
    case metric
    case relationship
    case isolation
    case controlFlow
    case configuration
    case history
    case similarity
}

/// A snapshot-local location reference an `EvidenceFact` may carry. Never a
/// `FindingID` (Invariant Q4/Q6 - location and evidence are not identity).
public struct EvidenceLocation: Codable, Hashable, Sendable {
    public let file: String?
    public let line: Int?
    public let column: Int?
    public let projectManifestPath: String?

    public init(
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        projectManifestPath: String? = nil
    ) {
        self.file = file
        self.line = line
        self.column = column
        self.projectManifestPath = projectManifestPath
    }
}
