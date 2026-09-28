/// Kind of observation or derived analysis a rule may require (addendum C).
/// A closed, enumerable vocabulary rather than an open registry: R2 commits to
/// a known set of capability *kinds*, matching the addendum's explicit
/// rejection of `OptionSet` in favor of a dependency graph, while keeping the
/// value type simple and exhaustively switchable. Growing the vocabulary is a
/// deliberate catalog change, not runtime configuration.
public enum AnalysisCapability: String, Codable, CaseIterable, Sendable {
    case syntax
    case metrics
    case symbols
    case types
    case references
    case ownership
    case isolation
    case controlFlow
    case dataFlow
    case moduleGraph
    case dependencyGraph
    case callGraph
    case buildConfiguration
    case packageManifest
    case xcodeProject
    case gitHistory
    case semanticSimilarity
    case runtimeEvidence
    case externalEvidence

    /// Direct prerequisites for this capability (e.g. `isolation` needs
    /// `syntax` to have run first). This is the DAG's edge set - domain
    /// knowledge that belongs with the vocabulary itself. Computing the
    /// *closure* across a set of enabled rules (FR-5) is the capability
    /// resolution engine's job, a separate downstream unit; this property
    /// only states one capability's immediate dependencies.
    public var directDependencies: Set<Self> {
        switch self {
        case .syntax, .gitHistory, .buildConfiguration, .runtimeEvidence, .externalEvidence:
            return []
        case .metrics, .symbols, .types, .references:
            return [.syntax]
        case .ownership:
            return [.syntax, .symbols]
        case .isolation:
            return [.syntax, .symbols, .types]
        case .controlFlow:
            return [.syntax, .symbols]
        case .dataFlow:
            return [.syntax, .symbols, .controlFlow]
        case .moduleGraph, .dependencyGraph:
            return [.symbols, .references]
        case .callGraph:
            return [.symbols, .references, .controlFlow]
        case .packageManifest:
            return [.buildConfiguration]
        case .xcodeProject:
            return [.buildConfiguration]
        case .semanticSimilarity:
            return [.syntax, .symbols]
        }
    }
}

/// A Rule Definition's declared capability requirements (PRD FR-4). Rules
/// declare capability *kinds*, never concrete sensors or analyzers - the
/// analyzer behind a capability is an implementation detail of the engine
/// (ADR 0001 Q4).
public struct RuleRequirements: Codable, Hashable, Sendable {
    public let capabilities: Set<AnalysisCapability>

    public init(_ capabilities: Set<AnalysisCapability>) {
        self.capabilities = capabilities
    }
}
