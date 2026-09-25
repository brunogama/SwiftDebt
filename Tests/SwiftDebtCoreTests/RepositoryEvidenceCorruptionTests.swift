import Foundation
import Testing

@testable import SwiftDebtCore

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

    @Test("Decoded evidence rejects noncanonical nested ordering")
    func rejectsNoncanonicalOrdering() throws {
        let canonical = try reportPayload()
        _ = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: canonical)

        let diagnostics = try mutatedReport { report in
            report["diagnostics"] = Array((report["diagnostics"] as! [Any]).reversed())
        }
        let capabilities = try mutatedReport { report in
            var rules = report["rules"] as! [[String: Any]]
            rules[0]["capabilities"] = Array((rules[0]["capabilities"] as! [Any]).reversed())
            report["rules"] = rules
        }
        let detections = try mutatedReport { report in
            var rules = report["rules"] as! [[String: Any]]
            rules[0]["detections"] = Array((rules[0]["detections"] as! [Any]).reversed())
            report["rules"] = rules
        }
        let facts = try mutatedReport { report in
            mutateFirstDetection(in: &report) { detection in
                var explanation = detection["explanation"] as! [String: Any]
                explanation["decisiveFacts"] = Array((explanation["decisiveFacts"] as! [Any]).reversed())
                detection["explanation"] = explanation
            }
        }
        let units = try mutatedReport { report in
            mutateFirstDetection(in: &report) { detection in
                var explanation = detection["explanation"] as! [String: Any]
                explanation["comparedUnits"] = Array((explanation["comparedUnits"] as! [Any]).reversed())
                detection["explanation"] = explanation
            }
        }
        let issues = try noncanonicalIssuePayload()

        for payload in [diagnostics, capabilities, detections, facts, units, issues] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(RepositoryEvidenceReport.self, from: payload)
            }
        }
    }

    @Test("Decoded evidence binds selectors to unique current-snapshot facts")
    func rejectsForgedDetectionReferences() throws {
        let duplicateSelector = try mutatedReport { report in
            var rules = report["rules"] as! [[String: Any]]
            var detections = rules[0]["detections"] as! [[String: Any]]
            detections[1] = detections[0]
            rules[0]["detections"] = detections
            report["rules"] = rules
        }
        let changedFact = try mutatedReport { report in
            mutateFirstDetection(in: &report) { detection in
                var explanation = detection["explanation"] as! [String: Any]
                var facts = explanation["decisiveFacts"] as! [[String: Any]]
                facts[0]["value"] = "tampered"
                explanation["decisiveFacts"] = facts
                detection["explanation"] = explanation
            }
        }
        let foreignLocation = try JSONEncoder().encode(
            canonicalReport(detectionFile: "Foreign.swift", sourceFiles: ["Input.swift"])
        )

        for payload in [duplicateSelector, changedFact, foreignLocation] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(RepositoryEvidenceReport.self, from: payload)
            }
        }
    }

    @Test("Canonical repository evidence orders every equal-prefix tie breaker")
    func canonicalOrderingTieBreakers() throws {
        let first = SourceLocation(file: "A.swift", line: 1, column: 1)
        let second = SourceLocation(file: "A.swift", line: 2, column: 1)
        let third = SourceLocation(file: "B.swift", line: 1, column: 1)
        let function = RepositoryComparedUnit(kind: .functionParameters, displayName: "b", location: first)
        let initializer = RepositoryComparedUnit(kind: .initializerParameters, displayName: "a", location: first)
        let namedFirst = RepositoryComparedUnit(kind: .functionParameters, displayName: "a", location: first)
        let later = RepositoryComparedUnit(kind: .functionParameters, displayName: "a", location: second)

        #expect(repositoryComparedUnitOrder(namedFirst, later))
        #expect(!repositoryComparedUnitOrder(later, namedFirst))
        #expect(repositoryComparedUnitOrder(function, initializer))
        #expect(repositoryComparedUnitOrder(namedFirst, function))

        let baseFact = RepositoryObservedFact(
            kind: "a", value: "a", evidenceClass: .metric, locations: [first]
        )
        let laterKind = RepositoryObservedFact(
            kind: "b", value: "a", evidenceClass: .metric, locations: [first]
        )
        let laterValue = RepositoryObservedFact(
            kind: "a", value: "b", evidenceClass: .metric, locations: [first]
        )
        let laterClass = RepositoryObservedFact(
            kind: "a", value: "a", evidenceClass: .syntax, locations: [first]
        )
        let laterLocation = RepositoryObservedFact(
            kind: "a", value: "a", evidenceClass: .metric, locations: [second]
        )
        let longerLocations = RepositoryObservedFact(
            kind: "a", value: "a", evidenceClass: .metric, locations: [first, second]
        )

        #expect(repositoryObservedFactOrder(baseFact, laterKind))
        #expect(repositoryObservedFactOrder(baseFact, laterValue))
        #expect(repositoryObservedFactOrder(baseFact, laterClass))
        #expect(repositoryObservedFactOrder(baseFact, laterLocation))
        #expect(!repositoryObservedFactOrder(laterLocation, baseFact))
        #expect(repositoryObservedFactOrder(baseFact, longerLocations))
        for pair in zip(RepositoryEvidenceClass.allCases, RepositoryEvidenceClass.allCases.dropFirst()) {
            #expect(repositoryEvidenceClassOrder(pair.0, pair.1))
        }

        let ruleA = try orderedDetection(ruleIdentity: "a", semanticRevision: 1, location: first, fingerprint: "a")
        let ruleB = try orderedDetection(ruleIdentity: "b", semanticRevision: 1, location: first, fingerprint: "a")
        let revisionB = try orderedDetection(
            ruleIdentity: "a", semanticRevision: 2, location: first, fingerprint: "a")
        let locationB = try orderedDetection(
            ruleIdentity: "a", semanticRevision: 1, location: second, fingerprint: "a")
        let fingerprintB = try orderedDetection(
            ruleIdentity: "a", semanticRevision: 1, location: first, fingerprint: "b")

        #expect(repositoryDetectionOrder(ruleA, ruleB))
        #expect(repositoryDetectionOrder(ruleA, revisionB))
        #expect(repositoryDetectionOrder(ruleA, locationB))
        #expect(!repositoryDetectionOrder(locationB, ruleA))
        #expect(repositoryDetectionOrder(ruleA, fingerprintB))

        let issueA = try RepositoryEvidenceIssue(code: "a", message: "b")
        let issueB = try RepositoryEvidenceIssue(code: "b", message: "a")
        let messageA = try RepositoryEvidenceIssue(code: "a", message: "a")
        #expect(repositoryIssueOrder(issueA, issueB))
        #expect(repositoryIssueOrder(messageA, issueA))

        let providerA = RepositoryProviderIdentity(name: "A", version: "1")
        let providerB = RepositoryProviderIdentity(name: "B", version: "1")
        let providerV2 = RepositoryProviderIdentity(name: "A", version: "2")
        let capabilityA = try RepositoryCapabilityEvidence(
            capability: "a", state: .available, provider: providerA
        )
        let capabilityB = try RepositoryCapabilityEvidence(
            capability: "b", state: .available, provider: providerA
        )
        let namedProviderB = try RepositoryCapabilityEvidence(
            capability: "a", state: .available, provider: providerB
        )
        let versionedProvider = try RepositoryCapabilityEvidence(
            capability: "a", state: .available, provider: providerV2
        )
        let failedCapability = try RepositoryCapabilityEvidence(
            capability: "a", state: .failed, provider: providerA, issue: issueA
        )
        #expect(repositoryCapabilityOrder(capabilityA, capabilityB))
        #expect(repositoryCapabilityOrder(capabilityA, namedProviderB))
        #expect(repositoryCapabilityOrder(capabilityA, versionedProvider))
        #expect(repositoryCapabilityOrder(capabilityA, failedCapability))

        let earlierDiagnostic = AnalysisDiagnostic(severity: .warning, message: "b", location: first)
        let laterDiagnostic = AnalysisDiagnostic(severity: .warning, message: "a", location: third)
        let errorDiagnostic = AnalysisDiagnostic(severity: .error, message: "b", location: first)
        let messageDiagnostic = AnalysisDiagnostic(severity: .warning, message: "a", location: first)
        #expect(repositoryDiagnosticOrder(earlierDiagnostic, laterDiagnostic))
        #expect(!repositoryDiagnosticOrder(laterDiagnostic, earlierDiagnostic))
        #expect(repositoryDiagnosticOrder(errorDiagnostic, earlierDiagnostic))
        #expect(repositoryDiagnosticOrder(messageDiagnostic, earlierDiagnostic))
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

    private func reportPayload() throws -> Data {
        try JSONEncoder().encode(canonicalReport())
    }

    private func canonicalReport(
        detectionFile: String = "Input.swift",
        sourceFiles: [String] = ["Input.swift"]
    ) throws -> RepositoryEvidenceReport {
        let snapshotDigest = try RepositoryDigest(
            value: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
        let detections = try [
            detection(file: detectionFile, line: 1, value: "first", snapshotDigest: snapshotDigest),
            detection(file: detectionFile, line: 10, value: "second", snapshotDigest: snapshotDigest),
        ]
        let provider = RepositoryProviderIdentity(name: "SwiftSyntax", version: "602.0.0")
        let rule = RepositoryRuleEvidence(
            ruleIdentity: "data-clumps",
            semanticRevision: 2,
            name: "Data Clumps",
            completionState: .complete,
            predicate: "Find repeated parameter groups.",
            capabilities: [
                try RepositoryCapabilityEvidence(capability: "syntax.z", state: .available, provider: provider),
                try RepositoryCapabilityEvidence(capability: "syntax.a", state: .available, provider: provider),
            ],
            detections: Array(detections.reversed()),
            issues: []
        )
        return RepositoryEvidenceReport(
            generator: "SwiftDebt test",
            snapshot: RepositorySnapshotIdentity(
                sourceFiles: sourceFiles,
                contentDigest: snapshotDigest,
                configuration: .standard,
                versionControl: nil
            ),
            rules: [rule],
            diagnostics: [
                AnalysisDiagnostic(
                    severity: .warning,
                    message: "Later warning.",
                    location: SourceLocation(file: sourceFiles[0], line: 30)
                ),
                AnalysisDiagnostic(
                    severity: .warning,
                    message: "Earlier warning.",
                    location: SourceLocation(file: sourceFiles[0], line: 20)
                ),
            ],
            summary: RepositoryEvidenceSummary(
                sourceFileCount: sourceFiles.count,
                completeRuleCount: 1,
                incompleteRuleCount: 0,
                detectionCount: detections.count,
                currentSnapshotNotice: "Current snapshot only."
            )
        )
    }

    private func detection(
        file: String,
        line: Int,
        value: String,
        snapshotDigest: RepositoryDigest
    ) throws -> RepositoryDetection {
        let locations = [
            SourceLocation(file: file, line: line),
            SourceLocation(file: file, line: line + 1),
        ]
        let units = locations.map { location in
            RepositoryComparedUnit(kind: .functionParameters, displayName: "unit-\(location.line)", location: location)
        }
        let facts = [
            RepositoryObservedFact(
                kind: "shared-elements",
                value: value,
                evidenceClass: .structural,
                locations: locations
            ),
            RepositoryObservedFact(
                kind: "occurrence-count",
                value: "2",
                evidenceClass: .metric,
                locations: locations
            ),
        ]
        let fingerprint = try repositoryEvidenceFingerprint(
            ruleIdentity: "data-clumps",
            semanticRevision: 2,
            decisiveFacts: facts,
            comparedUnits: units
        )
        let selector = RepositoryDetectionSelector(
            ruleIdentity: "data-clumps",
            semanticRevision: 2,
            snapshotDigest: snapshotDigest,
            location: locations[0],
            evidenceFingerprint: fingerprint
        )
        return RepositoryDetection(
            selector: selector,
            title: "Data Clumps",
            primaryLocation: locations[0],
            summary: "Repeated group.",
            explanation: RepositoryDetectionExplanation(
                predicate: "Two units share a group.",
                decisiveFacts: Array(facts.reversed()),
                comparedUnits: Array(units.reversed()),
                evidenceClasses: [.structural, .syntax, .metric],
                limitations: ["Syntax only."],
                refactoringDirection: "Introduce a value type.",
                documentationURL: "https://example.test/data-clumps"
            )
        )
    }

    private func orderedDetection(
        ruleIdentity: String,
        semanticRevision: UInt,
        location: SwiftDebtCore.SourceLocation,
        fingerprint: Character
    ) throws -> RepositoryDetection {
        let digest = try RepositoryDigest(value: String(repeating: "a", count: 64))
        return RepositoryDetection(
            selector: RepositoryDetectionSelector(
                ruleIdentity: ruleIdentity,
                semanticRevision: semanticRevision,
                snapshotDigest: digest,
                location: location,
                evidenceFingerprint: try RepositoryDigest(
                    value: String(repeating: fingerprint, count: 64)
                )
            ),
            title: "Detection",
            primaryLocation: location,
            summary: "Summary",
            explanation: RepositoryDetectionExplanation(
                predicate: "Predicate",
                decisiveFacts: [
                    RepositoryObservedFact(
                        kind: "fact", value: "value", evidenceClass: .syntax, locations: [location]
                    )
                ],
                comparedUnits: [
                    RepositoryComparedUnit(kind: .functionParameters, displayName: "unit", location: location)
                ],
                evidenceClasses: [.syntax],
                limitations: [],
                refactoringDirection: "Refactor.",
                documentationURL: "https://example.test"
            )
        )
    }

    private func mutatedReport(_ mutation: (inout [String: Any]) -> Void) throws -> Data {
        var report = try JSONSerialization.jsonObject(with: reportPayload()) as! [String: Any]
        mutation(&report)
        return try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    }

    private func noncanonicalIssuePayload() throws -> Data {
        try mutatedReport { report in
            var rules = report["rules"] as! [[String: Any]]
            var rule = rules[0]
            var capabilities = rule["capabilities"] as! [[String: Any]]
            let firstIssue: [String: Any] = ["code": "a", "message": "First issue."]
            let secondIssue: [String: Any] = ["code": "b", "message": "Second issue."]
            capabilities[0]["state"] = "failed"
            capabilities[0]["issue"] = firstIssue
            capabilities[1]["state"] = "failed"
            capabilities[1]["issue"] = secondIssue
            rule["capabilities"] = capabilities
            rule["completionState"] = "incomplete"
            rule["issues"] = [secondIssue, firstIssue]
            rules[0] = rule
            report["rules"] = rules
            var summary = report["summary"] as! [String: Any]
            summary["completeRuleCount"] = 0
            summary["incompleteRuleCount"] = 1
            report["summary"] = summary
        }
    }

    private func mutateFirstDetection(
        in report: inout [String: Any],
        _ mutation: (inout [String: Any]) -> Void
    ) {
        var rules = report["rules"] as! [[String: Any]]
        var detections = rules[0]["detections"] as! [[String: Any]]
        mutation(&detections[0])
        rules[0]["detections"] = detections
        report["rules"] = rules
    }
}
