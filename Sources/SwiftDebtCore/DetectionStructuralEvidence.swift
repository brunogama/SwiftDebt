/// Versioned, engine-derived evidence used only to propose Finding continuity.
///
/// The digests are computed from validated SwiftSyntax nodes. They are evidence,
/// not a caller-provided Finding identity, and reconciliation still requires a
/// unique assignment plus any provenance needed for a cross-file move.
public struct DetectionStructuralEvidence: Codable, Equatable, Sendable {
    public enum Algorithm: String, Codable, Sendable {
        case swiftSyntaxV1 = "swift-syntax-v1"
    }

    public let algorithm: Algorithm
    public let subjectDigest: CompilerEvidenceDigest
    public let enclosingDeclarationDigest: CompilerEvidenceDigest?

    package init(
        algorithm: Algorithm = .swiftSyntaxV1,
        subjectDigest: CompilerEvidenceDigest,
        enclosingDeclarationDigest: CompilerEvidenceDigest?
    ) {
        self.algorithm = algorithm
        self.subjectDigest = subjectDigest
        self.enclosingDeclarationDigest = enclosingDeclarationDigest
    }
}
