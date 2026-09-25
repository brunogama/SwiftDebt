import Foundation
import SwiftDebtCore
import Testing

@Suite("Repository evidence schema 1 contract")
struct RepositoryEvidenceContractTests {
    @Test("Unknown schema versions and report kinds fail before interpretation")
    func rejectsUnknownEnvelope() {
        let decoder = JSONDecoder()
        let version = Data(#"{"schemaVersion":2,"reportKind":"swiftdebt-repository-evidence"}"#.utf8)
        let kind = Data(#"{"schemaVersion":1,"reportKind":"other"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try decoder.decode(RepositoryEvidenceReport.self, from: version)
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(RepositoryEvidenceReport.self, from: kind)
        }
    }

    @Test("Capability states reject contradictory issue payloads")
    func rejectsContradictoryCapabilities() {
        let availableWithIssue = Data(
            #"{"capability":"syntax","state":"available","provider":{"name":"SwiftSyntax","version":"602.0.0"},"issue":{"code":"bad","message":"contradiction"}}"#
                .utf8
        )
        let failedWithoutIssue = Data(
            #"{"capability":"syntax","state":"failed","provider":{"name":"SwiftSyntax","version":"602.0.0"}}"#.utf8
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryCapabilityEvidence.self, from: availableWithIssue)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryCapabilityEvidence.self, from: failedWithoutIssue)
        }
    }

    @Test("Validated leaf evidence rejects empty decoded values")
    func rejectsInvalidLeafEvidence() {
        let emptyIssue = Data(#"{"code":" ","message":"message"}"#.utf8)
        let emptyRevision = Data(#"{"revision":"","workingTreeState":"clean"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryEvidenceIssue.self, from: emptyIssue)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryVersionControlIdentity.self, from: emptyRevision)
        }
    }

    @Test("Invalid repository analysis thresholds fail at construction")
    func validatesConfiguration() {
        #expect(throws: RepositoryEvidenceContractError.self) {
            try RepositoryAnalysisConfiguration(
                minimumDataClumpElements: 2,
                minimumDataClumpOccurrences: 2,
                minimumRepeatedSwitchOccurrences: 2,
                maximumSourceFiles: 1,
                maximumTotalSourceBytes: 1,
                maximumAnalysisUnitsPerRule: 1,
                maximumDataClumpComparisons: 1,
                maximumDetectionsPerRule: 1
            )
        }
    }
}
