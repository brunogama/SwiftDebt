/// Root shape of a Rule Catalog Manifest file: a flat list of rule entries
/// (addendum H). One YAML document may describe any number of rules.
struct RuleManifestFile {
    var rules: [RuleManifestEntry]

    static func parse(_ node: YAMLNode) throws -> Self {
        guard let rulesNode = node["rules"] else {
            throw RuleManifestError.malformedDocument(
                reason: "manifest is missing a top-level 'rules' key")
        }
        guard let items = rulesNode.sequenceItems else {
            throw RuleManifestError.malformedDocument(reason: "'rules' must be a sequence")
        }
        let rules = try items.map {
            item in
            try RuleManifestEntry(node: item)
        }
        return Self(rules: rules)
    }
}

/// One manifest entry, decoded field-for-field against `RuleDefinition`
/// (ADR 0001 Q9: YAML is the source of truth, Swift decodes and validates
/// it - the manifest never carries executable expressions). String-typed
/// enum fields are intentionally kept as `String` rather than converted
/// directly to the domain enum here, so that an invalid raw value becomes a
/// named `RuleManifestError.invalidEnumValue` from the validator rather than
/// an opaque parse failure.
struct RuleManifestEntry {
    var id: String
    var semanticRevision: Int
    var title: String
    var category: String
    var scope: String
    var detectionMode: String
    var requirements: [String]
    var evidence: RuleManifestEvidenceContract
    var supportState: String
    var provenance: RuleManifestProvenance?

    init(node: YAMLNode) throws {
        id = try Self.requiredString(node, "id")
        semanticRevision = try Self.requiredInt(node, "semanticRevision")
        title = try Self.requiredString(node, "title")
        category = try Self.requiredString(node, "category")
        scope = try Self.requiredString(node, "scope")
        detectionMode = try Self.requiredString(node, "detectionMode")
        requirements = try Self.stringList(node, "requirements")
        guard let evidenceNode = node["evidence"] else {
            throw RuleManifestError.malformedDocument(
                reason: "rule '\(id)' is missing 'evidence'")
        }
        evidence = try RuleManifestEvidenceContract(node: evidenceNode)
        supportState = try Self.requiredString(node, "supportState")
        provenance = try node["provenance"].map {
            node in
            try RuleManifestProvenance(node: node)
        }
    }

    private static func requiredString(
        _ node: YAMLNode, _ key: String
    ) throws -> String {
        guard let value = node[key]?.stringValue else {
            throw RuleManifestError.malformedDocument(
                reason: "manifest entry is missing required field '\(key)'")
        }
        return value
    }

    private static func requiredInt(
        _ node: YAMLNode, _ key: String
    ) throws -> Int {
        guard let value = node[key]?.intValue else {
            throw RuleManifestError.malformedDocument(
                reason: "manifest entry field '\(key)' must be an integer")
        }
        return value
    }

    private static func stringList(
        _ node: YAMLNode, _ key: String
    ) throws -> [String] {
        let listNode = node[key] ?? .sequence([])
        guard let items = listNode.sequenceItems else {
            throw RuleManifestError.malformedDocument(
                reason: "'\(key)' must be a sequence of strings")
        }
        return try items.map { item in
            guard let value = item.stringValue else {
                throw RuleManifestError.malformedDocument(
                    reason: "'\(key)' entries must be strings")
            }
            return value
        }
    }
}

/// Mirrors `EvidenceContract`: a required predicate plus zero or more
/// optional predicates.
struct RuleManifestEvidenceContract {
    var required: RuleManifestEvidencePredicate
    var optional: [RuleManifestEvidencePredicate]?

    init(node: YAMLNode) throws {
        guard let requiredNode = node["required"] else {
            throw RuleManifestError.malformedDocument(
                reason: "'evidence' is missing its required predicate")
        }
        required = try RuleManifestEvidencePredicate(node: requiredNode)
        if let optionalNode = node["optional"] {
            guard let items = optionalNode.sequenceItems else {
                throw RuleManifestError.malformedDocument(
                    reason: "'evidence.optional' must be a sequence")
            }
            optional = try items.map {
                item in
                try RuleManifestEvidencePredicate(node: item)
            }
        } else {
            optional = nil
        }
    }
}

/// Mirrors `RuleProvenance`.
struct RuleManifestProvenance {
    var researchItem: Int
    var note: String?

    init(node: YAMLNode) throws {
        guard let value = node["researchItem"]?.intValue else {
            throw RuleManifestError.malformedDocument(
                reason: "'provenance.researchItem' must be an integer")
        }
        researchItem = value
        note = node["note"]?.stringValue
    }
}

/// Mirrors `EvidencePredicate`'s fact/all/any/not algebra (addendum E).
/// Decoded as a keyed union: exactly one of `fact`, `all`, `any`, `not` must
/// be present on a given YAML mapping node.
indirect enum RuleManifestEvidencePredicate {
    case fact(key: String, kind: String)
    case all([Self])
    case any([Self])
    case not(Self)

    private static let knownKeys: Set<String> = ["fact", "all", "any", "not"]

    init(node: YAMLNode) throws {
        guard case .mapping(let pairs) = node else {
            throw RuleManifestError.malformedDocument(
                reason: "an evidence predicate node must be a mapping")
        }
        let keys = pairs.map(\.key)
        let known = keys.filter { Self.knownKeys.contains($0) }
        guard keys.count == 1, known.count == 1 else {
            let reason =
                "an evidence predicate node must have exactly one of "
                + "fact/all/any/not, found \(keys)"
            throw RuleManifestError.malformedDocument(reason: reason)
        }
        let onlyKey = known[0]
        // swiftlint:disable:next force_unwrapping
        let value = node[onlyKey]!
        switch onlyKey {
        case "fact":
            guard let key = value["key"]?.stringValue, let kind = value["kind"]?.stringValue else {
                throw RuleManifestError.malformedDocument(
                    reason: "a 'fact' node requires string 'key' and 'kind' fields")
            }
            self = .fact(key: key, kind: kind)
        case "all":
            self = .all(try Self.children(of: value, under: "all"))
        case "any":
            self = .any(try Self.children(of: value, under: "any"))
        default:
            self = .not(try Self(node: value))
        }
    }

    private static func children(
        of node: YAMLNode, under key: String
    ) throws -> [Self] {
        guard let items = node.sequenceItems else {
            throw RuleManifestError.malformedDocument(reason: "'\(key)' must be a sequence")
        }
        return try items.map { item in
            try Self(node: item)
        }
    }
}
