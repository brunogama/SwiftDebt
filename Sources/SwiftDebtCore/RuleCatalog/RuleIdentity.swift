/// Stable semantic identifier for a Rule Definition. Independent of catalog
/// order, source file, and implementation type (PRD FR-2, Invariant Q6).
/// Format/uniqueness validation belongs to the catalog validation unit, not here.
public struct RuleIdentity: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

/// Links a Rule Definition back to the 100-item research catalog. A single
/// research item may back multiple Rule Definitions (ADR 0001 Q1); each
/// decomposed definition still cites the same `researchItem`.
public struct RuleProvenance: Codable, Hashable, Sendable {
    public let researchItem: Int
    public let note: String?

    public init(researchItem: Int, note: String? = nil) {
        self.researchItem = researchItem
        self.note = note
    }
}

/// Independent compatibility axes (PRD glossary; addendum B).
public struct SemanticRevision: Codable, Hashable, Sendable, ExpressibleByIntegerLiteral {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public init(integerLiteral value: Int) { self.value = value }
}

public struct ImplementationRevision: Codable, Hashable, Sendable, ExpressibleByIntegerLiteral {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public init(integerLiteral value: Int) { self.value = value }
}

/// Evidence Revision compatibility: comparable at equal Semantic Revision
/// even when Evidence Revision differs (ADR 0001 Q10).
public struct EvidenceRevision: Codable, Hashable, Sendable, ExpressibleByIntegerLiteral {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public init(integerLiteral value: Int) { self.value = value }
}

/// Catalog category (addendum N). Metadata only; never determines execution.
public enum RuleCategory: String, Codable, CaseIterable, Sendable {
    case architecture
    case concurrency
    case memory
    case errorHandling
    case typeSafety
    case uiFramework
    case testing
    case build
    case objectiveCInterop
    case performance
    case ci
    case compilerEvolution
    case style
    case observability
}

/// Descriptive, non-executable metadata for a Rule Definition.
public struct RuleMetadata: Codable, Hashable, Sendable {
    public let title: String
    public let category: RuleCategory
    public let provenance: [RuleProvenance]
    public let supportState: SupportState

    public init(
        title: String,
        category: RuleCategory,
        provenance: [RuleProvenance],
        supportState: SupportState
    ) {
        self.title = title
        self.category = category
        self.provenance = provenance
        self.supportState = supportState
    }
}
