/// Maturity of a Rule Definition's claim. Implementation existence alone
/// never implies `.supported` (PRD FR-3). Promotion from `.partial` to
/// `.supported` requires the full Evidence Contract to be satisfiable with
/// passing positive/adversarial fixtures (ADR 0001 Q3) - enforced by the
/// catalog validation unit, not represented as extra state here.
public enum SupportState: String, Codable, CaseIterable, Sendable {
    case supported
    case partial
    case research
    case externalRuntimeRequired
    case notReliablyObservable
}

/// Epistemic classification of how a Detection was produced (addendum K).
/// Metadata, never severity, never probability.
public enum DetectionMode: String, Codable, CaseIterable, Sendable {
    case deterministic
    case derived
    case heuristic
    case historical
    case runtimeDependent
    case external
}

/// Where a Research Claim's evidence lives (addendum D). Broader scopes are
/// introduced only when a concrete claim exercises them (PRD FR-13/FR-14).
public enum RuleScope: String, Codable, CaseIterable, Sendable {
    case syntax
    case sourceUnit
    case repository
    case project
    case history
    case runtime
    case external
}
