/// TASK-004 acceptance-corpus entry: an honest `.partial` stub for
/// `concurrency.actor-reentrancy` (research #19, addendum E/J, ADR 0001 #11).
///
/// This is deliberately not a real implementation. ADR 0001 Q8 caps R2 at
/// intraprocedural analysis - single-function control flow plus
/// suspension-point tracking - and this repo ships no control-flow or
/// data-flow sensor yet. Promoting a reentrancy rule to `.supported` needs
/// every leaf of its Evidence Contract backed by a shipped sensor with
/// passing positive/adversarial fixtures (ADR 0001 Q3); none of the four
/// facts below have one. The point of cataloging this rule now, honestly
/// `.partial`, is proving the catalog can hold a real claim with a correct
/// Evidence Contract that nothing currently satisfies - without ever
/// reporting false absence (Invariant Q3, SM-2).
public enum ActorReentrancyRule {
    /// Evidence Contract per addendum E: all four in-function facts must
    /// hold for a reentrancy Detection to be justified. The facts are named
    /// and typed correctly against `EvidenceFactKind`; none needs to be
    /// satisfiable by any sensor that exists today.
    public static let evidenceContract = EvidenceContract(
        required: .all([
            .fact(EvidenceRequirement(key: "invariantEstablished", kind: .controlFlow)),
            .fact(EvidenceRequirement(key: "suspensionPoint", kind: .isolation)),
            .fact(EvidenceRequirement(key: "postSuspensionUse", kind: .controlFlow)),
            .fact(EvidenceRequirement(key: "noSufficientRevalidation", kind: .controlFlow)),
        ])
    )

    public static let definition = RuleDefinition(
        identity: RuleIdentity("concurrency.actor-reentrancy"),
        metadata: RuleMetadata(
            title: "Actor reentrancy after suspension",
            category: .concurrency,
            provenance: [
                RuleProvenance(
                    researchItem: 19,
                    note: "TASK-004 honest partial stub - ADR 0001 Q8 caps R2 at "
                        + "intraprocedural analysis; no control-flow/data-flow sensor exists"
                ),
            ],
            supportState: .partial
        ),
        scope: .sourceUnit,
        mode: .derived,
        requirements: RuleRequirements([.syntax, .isolation, .controlFlow, .dataFlow]),
        evidenceContract: evidenceContract,
        semanticRevision: SemanticRevision(1)
    )
}

/// Marker analysis context the reentrancy stub would observe against if a
/// real sensor existed (ADR 0001 Q8). `sourceText` is carried only so a
/// caller/test can hand this stub something that *looks* like a reentrancy
/// bug; `ActorReentrancyPartialStub` never reads it, because there is no
/// sensor in this repo capable of turning it into any of the four required
/// facts.
public struct ActorReentrancySourceUnitContext: AnalysisContextProtocol {
    public let sourceText: String

    public init(sourceText: String = "") {
        self.sourceText = sourceText
    }
}

/// Honest R2 stub for `concurrency.actor-reentrancy`. Always reports
/// `.unavailable(.capabilityNotProvided(.controlFlow))` and never emits a
/// Detection, regardless of input - see the type header on
/// `ActorReentrancyRule` for why. This is not "best effort with a fallback";
/// there is no code path in `detect` that can produce a Detection at all,
/// so it cannot regress into a false pass by later edits missing a branch.
public struct ActorReentrancyPartialStub: RuleImplementation {
    public typealias Context = ActorReentrancySourceUnitContext

    public let definition: RuleDefinition = ActorReentrancyRule.definition
    public let implementationRevision: ImplementationRevision = 1

    public init() {}

    /// The stub's honest observation result. Always `.unavailable` because
    /// no control-flow/data-flow sensor exists yet to establish any of the
    /// four required facts (ADR 0001 Q8) - never `.complete`, which would
    /// wrongly claim verified absence of reentrancy (Invariant Q3).
    public func observe(in context: Context) -> ObservationState {
        .unavailable(reason: .capabilityNotProvided(.controlFlow))
    }

    /// Never emits anything through `emit`: `DetectionEmitter` exposes no
    /// Detection-emission API yet, and `observe(in:)` already reports
    /// `.unavailable`, so there is nothing this stub could legitimately
    /// emit even once that API lands.
    public func detect(in context: Context, emit: DetectionEmitter) throws {
        _ = observe(in: context)
    }
}
