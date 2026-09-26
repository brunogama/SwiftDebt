import Foundation
import Testing

@testable import SwiftDebtCore

@Suite("Compatibility declaration coverage")
struct CompatibilityDeclarationCoverageTests {
    @Test("Persisted compatibility declarations reject malformed values")
    func compatibilityDeclarationDecoding() throws {
        let decoder = JSONDecoder()
        let invalidEvidence = Data(
            #"{"identifier":"invalid id","summary":"Valid summary."}"#.utf8
        )
        let invalidSemantic = Data(
            #"{"fromRevision":1,"supportedClaims":[],"rationale":"No claims."}"#.utf8
        )
        let invalidConfiguration = Data(
            #"{"fromRevision":1,"supportedClaims":["absence"],"conditions":[],"testEvidence":{"identifier":"compatibility.test","summary":"Valid summary."},"rationale":"No condition."}"#
                .utf8
        )
        let validSemantic = Data(
            #"{"fromRevision":1,"supportedClaims":["absence","continuity"],"rationale":"Both claims tested."}"#.utf8
        )
        let validConfiguration = Data(
            #"{"fromRevision":1,"supportedClaims":["absence","continuity"],"conditions":["maximum-file-bytes-nondecreasing"],"testEvidence":{"identifier":"compatibility.test","summary":"Valid summary."},"rationale":"Both claims tested."}"#
                .utf8
        )

        #expect(throws: DecodingError.self) {
            try decoder.decode(CompatibilityTestEvidence.self, from: invalidEvidence)
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(SemanticCompatibilityDeclaration.self, from: invalidSemantic)
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(ConfigurationCompatibilityDeclaration.self, from: invalidConfiguration)
        }
        #expect(
            try decoder.decode(SemanticCompatibilityDeclaration.self, from: validSemantic)
                .supportedClaims == [.absence, .continuity]
        )
        #expect(
            try decoder.decode(ConfigurationCompatibilityDeclaration.self, from: validConfiguration)
                .supportedClaims == [.absence, .continuity]
        )
    }

    @Test("Rule contracts sort multiple compatibility declarations canonically")
    func ruleContractSortsCompatibilityDeclarations() throws {
        let second = try #require(SemanticRevision(2))
        let semanticFirst = try #require(
            SemanticCompatibilityDeclaration(
                fromRevision: .initial,
                supportedClaims: [.continuity],
                rationale: "First revision tested."
            )
        )
        let semanticSecond = try #require(
            SemanticCompatibilityDeclaration(
                fromRevision: second,
                supportedClaims: [.absence],
                rationale: "Second revision tested."
            )
        )
        let evidence = try #require(
            CompatibilityTestEvidence(identifier: "compatibility.test", summary: "Tested through CLI.")
        )
        let configurationFirst = try #require(
            ConfigurationCompatibilityDeclaration(
                fromRevision: .initial,
                supportedClaims: [.continuity],
                conditions: [.maximumFileBytesNondecreasing],
                testEvidence: evidence,
                rationale: "First configuration direction tested."
            )
        )
        let configurationSecond = try #require(
            ConfigurationCompatibilityDeclaration(
                fromRevision: second,
                supportedClaims: [.absence],
                conditions: [.maximumFileBytesNondecreasing],
                testEvidence: evidence,
                rationale: "Second configuration direction tested."
            )
        )
        let contract = RuleContract(
            semanticRevision: second,
            semantics: "A tested rule.",
            rationale: "History remains auditable.",
            compatibilityDeclarations: [semanticSecond, semanticFirst],
            configurationCompatibilityDeclarations: [configurationSecond, configurationFirst]
        )

        #expect(contract.compatibilityDeclarations == [semanticFirst, semanticSecond])
        #expect(contract.configurationCompatibilityDeclarations == [configurationFirst, configurationSecond])
    }
}
