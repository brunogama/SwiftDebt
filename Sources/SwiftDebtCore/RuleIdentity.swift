public struct RuleNamespace: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    package init(validated rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    private static func isValid(_ value: String) -> Bool {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        return !segments.isEmpty
            && segments.allSatisfy { segment in
                guard let first = segment.first, first.isASCII, first.isLowercase else { return false }
                return segment.allSatisfy { character in
                    character.isASCII && (character.isLowercase || character.isNumber || character == "-")
                }
            }
    }
}

public struct RuleID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(_ rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    package init(validated rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    private static func isValid(_ value: String) -> Bool {
        guard let first = value.first, first.isASCII, first.isLowercase else { return false }
        return value.allSatisfy { character in
            character.isASCII && (character.isLowercase || character.isNumber || character == "-")
        }
    }
}

public struct RuleIdentity: Hashable, Sendable, CustomStringConvertible {
    public let namespace: RuleNamespace
    public let id: RuleID

    public init(namespace: RuleNamespace, id: RuleID) {
        self.namespace = namespace
        self.id = id
    }

    public var description: String { "\(namespace).\(id)" }
}

public struct SemanticRevision: Hashable, Comparable, Sendable, CustomStringConvertible {
    public static let initial = SemanticRevision(validated: 1)

    public let rawValue: UInt

    public init?(_ rawValue: UInt) {
        guard rawValue > 0 else { return nil }
        self.rawValue = rawValue
    }

    private init(validated rawValue: UInt) {
        self.rawValue = rawValue
    }

    public func successor() -> SemanticRevision? {
        guard rawValue < UInt.max else { return nil }
        return SemanticRevision(validated: rawValue + 1)
    }

    public func immediatelySucceeds(_ predecessor: SemanticRevision) -> Bool {
        predecessor.successor() == self
    }

    public static func < (lhs: SemanticRevision, rhs: SemanticRevision) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { String(rawValue) }
}

public enum RuleSeverity: String, CaseIterable, Equatable, Sendable {
    case information
    case warning
    case error
}

public struct RuleMetadata: Equatable, Sendable {
    public let name: String
    public let defaultSeverity: RuleSeverity
    public let remediation: String

    public init(name: String, defaultSeverity: RuleSeverity, remediation: String) {
        self.name = name
        self.defaultSeverity = defaultSeverity
        self.remediation = remediation
    }
}

public struct RuleContract: Equatable, Sendable {
    public let semanticRevision: SemanticRevision
    public let semantics: String
    public let rationale: String

    public init(semanticRevision: SemanticRevision, semantics: String, rationale: String) {
        self.semanticRevision = semanticRevision
        self.semantics = semantics
        self.rationale = rationale
    }
}

public struct RuleDescriptor: Equatable, Sendable {
    public let identity: RuleIdentity
    public let metadata: RuleMetadata
    public let contract: RuleContract

    public init(
        identity: RuleIdentity,
        metadata: RuleMetadata,
        contract: RuleContract
    ) {
        self.identity = identity
        self.metadata = metadata
        self.contract = contract
    }

    public var semanticRevision: SemanticRevision { contract.semanticRevision }
}
