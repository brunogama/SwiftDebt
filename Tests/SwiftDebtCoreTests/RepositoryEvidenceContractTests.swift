import Foundation
import SwiftDebtCore
import Testing

@Suite("Repository evidence schema 1 contract")
struct RepositoryEvidenceContractTests {
    @Test("Decoded incomplete evidence cannot claim complete absence")
    func decodedIncompleteEvidenceCannotProveAbsence() throws {
        let data = Data(
            """
            {
              "ruleIdentity": "forged",
              "semanticRevision": 0,
              "name": "Forged",
              "qualification": "Research",
              "completionState": "complete",
              "predicate": "No analysis was performed.",
              "capabilities": [],
              "detections": [],
              "issues": [
                { "code": "parse-failed", "message": "The source did not parse." }
              ]
            }
            """.utf8
        )

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RepositoryRuleEvidence.self, from: data)
        }
    }

    @Test("Decoded repository reports require at least one validated rule")
    func decodedReportCannotBeVacuouslyComplete() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "reportKind": "swiftdebt-repository-evidence",
              "generator": "SwiftDebt test",
              "snapshot": {
                "sourceFiles": ["Input.swift"],
                "contentDigest": {
                  "algorithm": "sha256",
                  "value": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                },
                "configuration": {
                  "minimumDataClumpElements": 3,
                  "minimumDataClumpOccurrences": 2,
                  "minimumRepeatedSwitchOccurrences": 2,
                  "maximumSourceFiles": 100,
                  "maximumTotalSourceBytes": 1000000,
                  "maximumAnalysisUnitsPerRule": 100,
                  "maximumDataClumpComparisons": 1000,
                  "maximumDetectionsPerRule": 100
                }
              },
              "rules": [],
              "diagnostics": [],
              "summary": {
                "sourceFileCount": 1,
                "completeRuleCount": 0,
                "incompleteRuleCount": 0,
                "detectionCount": 0,
                "currentSnapshotNotice": "No rules were analyzed."
              }
            }
            """.utf8
        )

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RepositoryEvidenceReport.self, from: data)
        }
    }

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
