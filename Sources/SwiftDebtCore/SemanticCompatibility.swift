public enum SemanticCompatibilityClaim: String, Codable, CaseIterable, Hashable, Sendable {
    case continuity
    case absence
}

/// A rule-owned declaration evaluated from an earlier Semantic Revision into
/// the revision of the containing ``RuleContract``.
///
/// A declaration only relaxes the Semantic Revision equality check for its
/// listed claims. Configuration, capability, source, scope, engine, and
/// evidence requirements remain independently fail closed.
public struct SemanticCompatibilityDeclaration: Codable, Equatable, Hashable, Sendable {
    public let fromRevision: SemanticRevision
    public let supportedClaims: [SemanticCompatibilityClaim]
    public let rationale: String

    public init?(
        fromRevision: SemanticRevision,
        supportedClaims: [SemanticCompatibilityClaim],
        rationale: String
    ) {
        let claims = Array(Set(supportedClaims)).sorted { $0.rawValue < $1.rawValue }
        guard !claims.isEmpty, Self.isValidRationale(rationale) else { return nil }
        self.fromRevision = fromRevision
        self.supportedClaims = claims
        self.rationale = rationale
    }

    private enum CodingKeys: String, CodingKey {
        case fromRevision
        case supportedClaims
        case rationale
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let revisionValue = try values.decode(UInt.self, forKey: .fromRevision)
        let supportedClaims = try values.decode(
            [SemanticCompatibilityClaim].self,
            forKey: .supportedClaims
        )
        let rationale = try values.decode(String.self, forKey: .rationale)
        let canonicalClaims = Array(Set(supportedClaims)).sorted { $0.rawValue < $1.rawValue }
        guard
            supportedClaims == canonicalClaims,
            let revision = SemanticRevision(revisionValue),
            let declaration = Self(
                fromRevision: revision,
                supportedClaims: supportedClaims,
                rationale: rationale
            )
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .fromRevision,
                in: values,
                debugDescription:
                    "Semantic compatibility declarations require a prior revision, canonical claims, and rationale."
            )
        }
        self = declaration
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fromRevision.rawValue, forKey: .fromRevision)
        try values.encode(supportedClaims, forKey: .supportedClaims)
        try values.encode(rationale, forKey: .rationale)
    }

    private static func isValidRationale(_ value: String) -> Bool {
        !value.isEmpty
            && value.first?.isWhitespace == false
            && value.last?.isWhitespace == false
            && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
