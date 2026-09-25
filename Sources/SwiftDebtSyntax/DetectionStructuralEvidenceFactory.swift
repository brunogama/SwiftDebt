import Foundation
import SwiftDebtCore
import SwiftSyntax

enum DetectionStructuralEvidenceFactory {
    static func make(subject: Syntax) throws -> DetectionStructuralEvidence {
        let subjectDigest = try digest(domain: "swiftdebt-continuity-subject-v1") { input in
            appendTokens(of: subject, to: &input)
        }
        let declarationDigest = try enclosingDeclarations(of: subject).map { declarations in
            try digest(domain: "swiftdebt-continuity-declaration-v1") { input in
                input.append(UInt64(declarations.count))
                for declaration in declarations {
                    input.append(String(describing: declaration.kind))
                    appendHeaderTokens(of: declaration, to: &input)
                }
            }
        }
        return DetectionStructuralEvidence(
            subjectDigest: subjectDigest,
            enclosingDeclarationDigest: declarationDigest
        )
    }

    private static func enclosingDeclarations(of subject: Syntax) -> [Syntax]? {
        var declarations: [Syntax] = []
        var ancestor = subject.parent
        while let current = ancestor {
            if current.as(DeclSyntax.self) != nil, !current.is(IfConfigDeclSyntax.self) {
                declarations.append(current)
            }
            ancestor = current.parent
        }
        guard !declarations.isEmpty else { return nil }
        return Array(declarations.reversed())
    }

    private static func appendHeaderTokens(of declaration: Syntax, to input: inout StructuralDigestInput) {
        let tokens = Array(declaration.tokens(viewMode: .sourceAccurate))
        let header = tokens.prefix { $0.tokenKind != .leftBrace }
        input.append(UInt64(header.count))
        for token in header { input.append(token.text) }
    }

    private static func appendTokens(of syntax: Syntax, to input: inout StructuralDigestInput) {
        let tokens = Array(syntax.tokens(viewMode: .sourceAccurate))
        input.append(UInt64(tokens.count))
        for token in tokens { input.append(token.text) }
    }

    private static func digest(
        domain: String,
        append: (inout StructuralDigestInput) -> Void
    ) throws -> CompilerEvidenceDigest {
        var input = StructuralDigestInput()
        input.append(domain)
        append(&input)
        return try CompilerEvidenceDigest(value: input.hexDigest())
    }
}

private struct StructuralDigestInput {
    private var data = Data()

    mutating func append(_ value: String) {
        let bytes = Data(value.utf8)
        append(UInt64(bytes.count))
        data.append(bytes)
    }

    mutating func append(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { data.append(contentsOf: $0) }
    }

    func hexDigest() -> String { StructuralSHA256.hexDigest(data) }
}
