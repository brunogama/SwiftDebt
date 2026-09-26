import Foundation
import Testing

@testable import SwiftDebtCore

@Suite("Semantic compatibility persistence")
struct SemanticCompatibilityTests {
    @Test("Canonical declarations round-trip through JSON")
    func canonicalDeclarationRoundTrip() throws {
        let declaration = try #require(
            SemanticCompatibilityDeclaration(
                fromRevision: .initial,
                supportedClaims: [.continuity, .absence, .continuity],
                rationale: "Revision 2 preserves both lifecycle interpretations."
            )
        )

        let encoded = try JSONEncoder().encode(declaration)
        let decoded = try JSONDecoder().decode(
            SemanticCompatibilityDeclaration.self,
            from: encoded
        )

        #expect(decoded == declaration)
        #expect(decoded.supportedClaims == [.absence, .continuity])
    }

    @Test(
        "Persisted declarations reject noncanonical or invalid values",
        arguments: [
            """
            {
              "fromRevision": 1,
              "supportedClaims": ["continuity", "absence"],
              "rationale": "Claims are out of canonical order."
            }
            """,
            """
            {
              "fromRevision": 1,
              "supportedClaims": ["absence", "absence"],
              "rationale": "Duplicate claims are not canonical."
            }
            """,
            """
            {
              "fromRevision": 0,
              "supportedClaims": ["continuity"],
              "rationale": "Revision zero is invalid."
            }
            """,
            """
            {
              "fromRevision": 1,
              "supportedClaims": ["continuity"],
              "rationale": " Invalid surrounding whitespace."
            }
            """,
        ]
    )
    func rejectsInvalidPersistence(payload: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                SemanticCompatibilityDeclaration.self,
                from: Data(payload.utf8)
            )
        }
    }
}
