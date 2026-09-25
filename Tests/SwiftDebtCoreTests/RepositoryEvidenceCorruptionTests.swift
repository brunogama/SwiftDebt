import Foundation
import SwiftDebtCore
import Testing

@Suite("Repository evidence corruption handling")
struct RepositoryEvidenceCorruptionTests {
    @Test("Decoded configurations reject every invalid threshold class")
    func rejectsInvalidConfigurationPayloads() throws {
        let invalidOccurrences = try configurationData(
            minimumDataClumpOccurrences: 1
        )
        let invalidBudget = try configurationData(
            maximumSourceFiles: 0
        )

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryAnalysisConfiguration.self, from: invalidOccurrences)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryAnalysisConfiguration.self, from: invalidBudget)
        }
    }

    @Test("Decoded digests require the canonical algorithm and value")
    func rejectsInvalidDigestPayloads() {
        let invalidAlgorithm = Data(
            #"{"algorithm":"sha512","value":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#.utf8
        )
        let invalidValue = Data(#"{"algorithm":"sha256","value":"ABC"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryDigest.self, from: invalidAlgorithm)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryDigest.self, from: invalidValue)
        }
    }

    @Test("Decoded issue messages must contain usable text")
    func rejectsEmptyIssueMessages() {
        let payload = Data(#"{"code":"parse-failed","message":"\n"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryEvidenceIssue.self, from: payload)
        }
    }

    @Test("Decoded rule completion must agree with capabilities and issues")
    func rejectsContradictoryRuleCompletion() throws {
        let issue = try RepositoryEvidenceIssue(code: "provider-failed", message: "Provider failed.")
        let capability = try RepositoryCapabilityEvidence(
            capability: "syntax.parameters",
            state: .failed,
            provider: RepositoryProviderIdentity(name: "SwiftSyntax", version: "602.0.0"),
            issue: issue
        )
        let forged = RepositoryRuleEvidence(
            ruleIdentity: "data-clumps",
            semanticRevision: 2,
            name: "Data Clumps",
            completionState: .complete,
            predicate: "Find repeated parameter groups.",
            capabilities: [capability],
            detections: [],
            issues: []
        )

        let payload = try JSONEncoder().encode(forged)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryRuleEvidence.self, from: payload)
        }
    }

    @Test("Error diagnostics require every rule to record a parse failure")
    func rejectsUnexplainedErrorDiagnostics() throws {
        let capability = try RepositoryCapabilityEvidence(
            capability: "syntax.parameters",
            state: .available,
            provider: RepositoryProviderIdentity(name: "SwiftSyntax", version: "602.0.0")
        )
        let rule = RepositoryRuleEvidence(
            ruleIdentity: "data-clumps",
            semanticRevision: 2,
            name: "Data Clumps",
            completionState: .complete,
            predicate: "Find repeated parameter groups.",
            capabilities: [capability],
            detections: [],
            issues: []
        )
        let report = RepositoryEvidenceReport(
            generator: "SwiftDebt test",
            snapshot: RepositorySnapshotIdentity(
                sourceFiles: ["Input.swift"],
                contentDigest: try RepositoryDigest(
                    value: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                ),
                configuration: .standard,
                versionControl: nil
            ),
            rules: [rule],
            diagnostics: [
                AnalysisDiagnostic(
                    severity: .error,
                    message: "Input did not parse.",
                    location: SourceLocation(file: "Input.swift", line: 1)
                )
            ],
            summary: RepositoryEvidenceSummary(
                sourceFileCount: 1,
                completeRuleCount: 1,
                incompleteRuleCount: 0,
                detectionCount: 0,
                currentSnapshotNotice: "Current snapshot only."
            )
        )

        let payload = try JSONEncoder().encode(report)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryEvidenceReport.self, from: payload)
        }

        let providerIssue = try RepositoryEvidenceIssue(
            code: "provider-failed",
            message: "Syntax provider failed."
        )
        let incompleteRule = RepositoryRuleEvidence(
            ruleIdentity: "data-clumps",
            semanticRevision: 2,
            name: "Data Clumps",
            completionState: .incomplete,
            predicate: "Find repeated parameter groups.",
            capabilities: [
                try RepositoryCapabilityEvidence(
                    capability: "syntax.parameters",
                    state: .failed,
                    provider: RepositoryProviderIdentity(name: "SwiftSyntax", version: "602.0.0"),
                    issue: providerIssue
                )
            ],
            detections: [],
            issues: [providerIssue]
        )
        let malformed = RepositoryEvidenceReport(
            generator: "SwiftDebt test",
            snapshot: RepositorySnapshotIdentity(
                sourceFiles: ["../Input.swift"],
                contentDigest: try RepositoryDigest(
                    value: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
                ),
                configuration: .standard,
                versionControl: nil
            ),
            rules: [incompleteRule],
            diagnostics: report.diagnostics,
            summary: RepositoryEvidenceSummary(
                sourceFileCount: 1,
                completeRuleCount: 0,
                incompleteRuleCount: 1,
                detectionCount: 0,
                currentSnapshotNotice: "Current snapshot only."
            )
        )

        let malformedPayload = try JSONEncoder().encode(malformed)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositoryEvidenceReport.self, from: malformedPayload)
        }
    }

    private func configurationData(
        minimumDataClumpOccurrences: Int = 2,
        maximumSourceFiles: Int = 100
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "minimumDataClumpElements": 3,
            "minimumDataClumpOccurrences": minimumDataClumpOccurrences,
            "minimumRepeatedSwitchOccurrences": 2,
            "maximumSourceFiles": maximumSourceFiles,
            "maximumTotalSourceBytes": 1_000_000,
            "maximumAnalysisUnitsPerRule": 100,
            "maximumDataClumpComparisons": 1_000,
            "maximumDetectionsPerRule": 100,
        ])
    }
}
