public enum LifecycleConfigurationDimension: String, Codable, CaseIterable, Hashable, Sendable {
    case sourceSelectionKind = "source-selection-kind"
    case excludedSourcePrefixes = "excluded-source-prefixes"
    case maximumFileBytes = "maximum-file-bytes"
    case selectedRuleIdentities = "selected-rule-identities"
}

/// A typed directional condition that a rule has tested for lifecycle claims.
public enum ConfigurationCompatibilityCondition: String, Codable, CaseIterable, Hashable, Sendable {
    case maximumFileBytesNondecreasing = "maximum-file-bytes-nondecreasing"

    public var dimension: LifecycleConfigurationDimension {
        switch self {
        case .maximumFileBytesNondecreasing: .maximumFileBytes
        }
    }
}

/// An auditable reference to the test that supports a compatibility declaration.
public struct CompatibilityTestEvidence: Codable, Equatable, Hashable, Sendable {
    public let identifier: String
    public let summary: String

    public init?(identifier: String, summary: String) {
        guard Self.isValidIdentifier(identifier), Self.isValidText(summary) else { return nil }
        self.identifier = identifier
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case summary
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try values.decode(String.self, forKey: .identifier)
        let summary = try values.decode(String.self, forKey: .summary)
        guard let evidence = Self(identifier: identifier, summary: summary) else {
            throw DecodingError.dataCorruptedError(
                forKey: .identifier,
                in: values,
                debugDescription: "Compatibility test evidence requires a stable identifier and summary."
            )
        }
        self = evidence
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.allSatisfy { character in
                character.isASCII
                    && (character.isLetter || character.isNumber
                        || character == "." || character == "-" || character == "_")
            }
    }

    private static func isValidText(_ value: String) -> Bool {
        !value.isEmpty
            && value.first?.isWhitespace == false
            && value.last?.isWhitespace == false
            && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}

/// A destination rule's tested permission for specific effective-configuration
/// changes from one prior Semantic Revision.
public struct ConfigurationCompatibilityDeclaration: Codable, Equatable, Hashable, Sendable {
    public let fromRevision: SemanticRevision
    public let supportedClaims: [SemanticCompatibilityClaim]
    public let conditions: [ConfigurationCompatibilityCondition]
    public let testEvidence: CompatibilityTestEvidence
    public let rationale: String

    public init?(
        fromRevision: SemanticRevision,
        supportedClaims: [SemanticCompatibilityClaim],
        conditions: [ConfigurationCompatibilityCondition],
        testEvidence: CompatibilityTestEvidence,
        rationale: String
    ) {
        let claims = Array(Set(supportedClaims)).sorted { $0.rawValue < $1.rawValue }
        let conditions = Array(Set(conditions)).sorted { $0.rawValue < $1.rawValue }
        guard !claims.isEmpty, !conditions.isEmpty, Self.isValidRationale(rationale) else { return nil }
        self.fromRevision = fromRevision
        self.supportedClaims = claims
        self.conditions = conditions
        self.testEvidence = testEvidence
        self.rationale = rationale
    }

    private enum CodingKeys: String, CodingKey {
        case fromRevision
        case supportedClaims
        case conditions
        case testEvidence
        case rationale
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let revisionValue = try values.decode(UInt.self, forKey: .fromRevision)
        let claims = try values.decode([SemanticCompatibilityClaim].self, forKey: .supportedClaims)
        let conditions = try values.decode(
            [ConfigurationCompatibilityCondition].self,
            forKey: .conditions
        )
        let testEvidence = try values.decode(CompatibilityTestEvidence.self, forKey: .testEvidence)
        let rationale = try values.decode(String.self, forKey: .rationale)
        let canonicalClaims = Array(Set(claims)).sorted { $0.rawValue < $1.rawValue }
        let canonicalConditions = Array(Set(conditions)).sorted { $0.rawValue < $1.rawValue }
        guard
            claims == canonicalClaims,
            conditions == canonicalConditions,
            let revision = SemanticRevision(revisionValue),
            let declaration = Self(
                fromRevision: revision,
                supportedClaims: claims,
                conditions: conditions,
                testEvidence: testEvidence,
                rationale: rationale
            )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .fromRevision,
                in: values,
                debugDescription:
                    "Configuration compatibility requires canonical claims, typed conditions, "
                    + "test evidence, and rationale."
            )
        }
        self = declaration
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fromRevision.rawValue, forKey: .fromRevision)
        try values.encode(supportedClaims, forKey: .supportedClaims)
        try values.encode(conditions, forKey: .conditions)
        try values.encode(testEvidence, forKey: .testEvidence)
        try values.encode(rationale, forKey: .rationale)
    }

    package var canonicalOrderKey: String {
        let claims = supportedClaims.map(\.rawValue).joined(separator: ",")
        let conditions = conditions.map(\.rawValue).joined(separator: ",")
        return "\(fromRevision.rawValue):\(claims):\(conditions):\(testEvidence.identifier)"
    }

    private static func isValidRationale(_ value: String) -> Bool {
        !value.isEmpty
            && value.first?.isWhitespace == false
            && value.last?.isWhitespace == false
            && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
