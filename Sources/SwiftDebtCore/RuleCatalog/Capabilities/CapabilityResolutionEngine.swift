/// Resolves the set of `AnalysisCapability` values a collection of enabled
/// Rule Definitions actually needs (PRD FR-5, addendum C).
///
/// `AnalysisCapability.directDependencies` states only one capability's
/// immediate prerequisites - a fixed edge set of the capability DAG. This
/// engine walks that DAG per enabled rule to compute the *transitive
/// closure* across every rule's declared `RuleRequirements`, and records,
/// for each capability in the closure, which enabled rule(s) pulled it in.
///
/// Tracing is per-rule rather than a single flat union: each rule's own
/// requirements are walked to a fixed point independently, and the
/// contributing rule's identity is attached to every capability reached
/// during that walk - including capabilities reached only by following
/// dependency edges, not just the rule's directly-declared ones. This is
/// what makes the closure inspectable (FR-5) and lets a caller answer
/// "does anything still need this capability?" after a rule is disabled
/// (FR-6): disabled rules never enter the walk, so they can never leave a
/// trace behind, and re-resolving after removing a rule from the enabled
/// set drops every capability whose only contributor was that rule.
public struct CapabilityResolutionEngine: Sendable {
    public init() {}

    /// Computes the capability closure for a set of enabled rules.
    ///
    /// Disabled rules contribute nothing (FR-6): only `enabledRules` is
    /// walked, so a rule that is absent from this collection - whether it
    /// was never enabled or was removed by the caller - cannot appear as a
    /// contributor and cannot keep any capability in the closure alive.
    public func resolve<Rules: Sequence>(enabledRules: Rules) -> CapabilityResolution
    where Rules.Element == RuleDefinition {
        var contributors: [AnalysisCapability: Set<RuleIdentity>] = [:]

        for rule in enabledRules {
            var frontier = rule.requirements.capabilities
            var visited: Set<AnalysisCapability> = []

            while let capability = frontier.popFirst() {
                guard visited.insert(capability).inserted else { continue }
                contributors[capability, default: []].insert(rule.identity)
                frontier.formUnion(capability.directDependencies)
            }
        }

        return CapabilityResolution(contributors: contributors)
    }
}

/// The inspectable result of a capability resolution (PRD FR-5). Exposes
/// both the flat closure (`capabilities`) and, per capability, which
/// enabled rule(s) required it - directly or through dependency chaining.
public struct CapabilityResolution: Hashable, Sendable {
    private let contributors: [AnalysisCapability: Set<RuleIdentity>]

    init(contributors: [AnalysisCapability: Set<RuleIdentity>]) {
        self.contributors = contributors
    }

    /// The full transitive closure of capabilities actually needed by the
    /// enabled rules that produced this resolution.
    public var capabilities: Set<AnalysisCapability> {
        Set(contributors.keys)
    }

    /// Whether any enabled rule needs `capability`, directly or through a
    /// dependency chain.
    public func isNeeded(_ capability: AnalysisCapability) -> Bool {
        contributors[capability] != nil
    }

    /// The enabled rules whose requirements pulled `capability` into the
    /// closure. Empty when `capability` is not needed at all - the
    /// "removing the last consumer removes that work" contract (FR-6) is
    /// this set becoming empty for a capability once its only contributing
    /// rule(s) are no longer in the enabled set passed to `resolve`.
    public func rules(requiring capability: AnalysisCapability) -> Set<RuleIdentity> {
        contributors[capability] ?? []
    }
}
