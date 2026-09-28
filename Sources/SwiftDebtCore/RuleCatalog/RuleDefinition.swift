/// What SwiftDebt claims about a Research Claim: identity, scope, mode,
/// requirements, and evidence contract (addendum B). Independent of any
/// particular `RuleImplementation` (Invariant Q2) - a definition can exist,
/// cataloged, with no implementation at all (PRD FR-1/FR-3).
public struct RuleDefinition: Codable, Hashable, Sendable {
    public let identity: RuleIdentity
    public let metadata: RuleMetadata
    public let scope: RuleScope
    public let mode: DetectionMode
    public let requirements: RuleRequirements
    public let evidenceContract: EvidenceContract
    public let semanticRevision: SemanticRevision

    public init(
        identity: RuleIdentity,
        metadata: RuleMetadata,
        scope: RuleScope,
        mode: DetectionMode,
        requirements: RuleRequirements,
        evidenceContract: EvidenceContract,
        semanticRevision: SemanticRevision
    ) {
        self.identity = identity
        self.metadata = metadata
        self.scope = scope
        self.mode = mode
        self.requirements = requirements
        self.evidenceContract = evidenceContract
        self.semanticRevision = semanticRevision
    }
}

/// Scope-appropriate analysis context a `RuleImplementation` observes
/// against (PRD FR-14). Left as a marker protocol here: the concrete
/// contexts (source-unit syntax context, project/manifest context, etc.) are
/// a downstream unit's responsibility once `RuleScope` has real consumers.
public protocol AnalysisContextProtocol: Sendable {}

/// Sink a `RuleImplementation` emits Detections through. Left as a marker
/// protocol for the same reason as `AnalysisContextProtocol` - Detection
/// construction and R1 reconciliation wiring are out of this pilot's scope.
public protocol DetectionEmitter: Sendable {}

/// How this release observes a Rule Definition's claim (addendum B).
/// Implementation Revision may change (optimization, bug fixes) without
/// necessarily changing the definition's Semantic Revision.
public protocol RuleImplementation: Sendable {
    associatedtype Context: AnalysisContextProtocol

    var definition: RuleDefinition { get }
    var implementationRevision: ImplementationRevision { get }

    func detect(in context: Context, emit: DetectionEmitter) throws
}
