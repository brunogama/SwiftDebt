import Foundation
import Testing

@testable import SwiftDebtCore

@Suite("Compiler evidence report contract")
struct CompilerEvidenceReportTests {
    @Test("Canonical schema 1 report is deterministic and round trips")
    func canonicalReportRoundTrips() throws {
        let report = try makeReport()
        let encoded = try renderJSON(report)
        let expected = try fixture("canonical-report.golden.json")
        let decoded = try JSONDecoder().decode(CompilerEvidenceReport.self, from: Data(encoded.utf8))

        #expect(encoded == expected)
        #expect(decoded == report)
        #expect(decoded.schemaVersion == CompilerEvidenceReportSchema.currentVersion)
        #expect(decoded.reportKind == "swiftdebt-compiler-evidence")
        #expect(decoded.provenance.analysisMode == .compilerBacked)
        #expect(decoded.provenance.buildConfiguration.compilationConditions == ["DEBUG", "FEATURE_A"])
    }

    @Test("Unavailable and ambiguous states cannot masquerade as values or selected targets")
    func unavailableAndAmbiguousEvidenceFailClosed() throws {
        let report = try makeReport()
        let encoded = try JSONEncoder().encode(report)
        let root = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let availability = try #require(root["availability"] as? [String: Any])
        let typeChecking = try #require(availability["typeChecking"] as? [String: Any])
        let macroExpansion = try #require(availability["macroExpansion"] as? [String: Any])
        let nameBinding = try #require(availability["nameBinding"] as? [String: Any])

        #expect(typeChecking["state"] as? String == "available")
        #expect(typeChecking["issue"] == nil)
        #expect(macroExpansion["state"] as? String == "unavailable")
        #expect(macroExpansion["value"] == nil)
        #expect(nameBinding["state"] as? String == "ambiguous")
        #expect(nameBinding["target"] == nil)

        #expect(report.availability.typeChecking.isAvailable)
        #expect(!report.availability.macroExpansion.isAvailable)
        #expect(!report.availability.nameBinding.isAvailable)
        #expect(report.availability.typeChecking.issue == nil)
        #expect(report.availability.macroExpansion.issue?.code == "unstable-compiler-output")
        #expect(report.availability.nameBinding.issue?.code == "multiple-candidates")
    }

    @Test("Invalid availability payloads are rejected")
    func invalidAvailabilityPayloadsAreRejected() {
        let issueOnAvailable = Data(
            #"{"state":"available","issue":{"code":"unexpected","message":"must fail"}}"#.utf8
        )
        let missingUnavailableIssue = Data(#"{"state":"unavailable"}"#.utf8)
        let unknownState = Data(#"{"state":"guessed"}"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompilerEvidenceAvailability.self, from: issueOnAvailable)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompilerEvidenceAvailability.self, from: missingUnavailableIssue)
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompilerEvidenceAvailability.self, from: unknownState)
        }
    }

    @Test("Source identity supports Git, archives, and explicit unavailability")
    func sourceIdentityStatesRemainExplicit() throws {
        let digest = try CompilerEvidenceDigest(
            value: "3333333333333333333333333333333333333333333333333333333333333333"
        )
        let revisions: [CompilerSourceRevision] = [
            .versionControl(
                revision: try CompilerRevisionIdentifier("abc123"),
                workingTreeState: .clean,
                contentDigest: digest
            ),
            .contentDigest(digest),
            .unavailable(
                CompilerEvidenceIssue(
                    code: "source-identity-unavailable",
                    message: "No revision or source digest was supplied."
                )
            ),
        ]

        for revision in revisions {
            let encoded = try JSONEncoder().encode(revision)
            #expect(try JSONDecoder().decode(CompilerSourceRevision.self, from: encoded) == revision)
        }
        #expect(revisions.map(\.state) == [.versionControl, .contentDigest, .unavailable])
    }

    @Test("Malformed or unknown source digests fail closed")
    func invalidDigestsAreRejected() {
        #expect(throws: CompilerEvidenceContractError.self) {
            try CompilerEvidenceDigest(value: "unknown")
        }
        #expect(throws: CompilerEvidenceContractError.self) {
            try CompilerRevisionIdentifier("")
        }
        let malformed = Data(#"{"algorithm":"sha256","value":"ABC123"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(CompilerEvidenceDigest.self, from: malformed)
        }
    }

    @Test("Source identity states reject fields from another state")
    func sourceIdentityRejectsMixedStates() {
        let digest =
            #"{"algorithm":"sha256","value":"3333333333333333333333333333333333333333333333333333333333333333"}"#
        let mixedPayloads = [
            Data(
                #"{"state":"version-control","revision":"abc","workingTreeState":"clean","contentDigest":\#(digest),"issue":{"code":"mixed","message":"invalid"}}"#
                    .utf8
            ),
            Data(
                #"{"state":"content-digest","revision":"abc","contentDigest":\#(digest)}"#.utf8
            ),
            Data(
                #"{"state":"unavailable","contentDigest":\#(digest),"issue":{"code":"mixed","message":"invalid"}}"#.utf8
            ),
        ]

        for payload in mixedPayloads {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(CompilerSourceRevision.self, from: payload)
            }
        }
    }

    private func makeReport() throws -> CompilerEvidenceReport {
        let unavailable = CompilerEvidenceIssue(
            code: "unstable-compiler-output",
            message: "The compiler output format is not a supported semantic boundary."
        )
        let ambiguous = CompilerEvidenceIssue(
            code: "multiple-candidates",
            message: "More than one declaration remains possible; no target was selected."
        )
        return CompilerEvidenceReport(
            provenance: CompilerEvidenceProvenance(
                generatorVersion: "0.1.0",
                compilerToolchain: CompilerToolchainIdentity(
                    compilerName: "Apple Swift",
                    compilerVersion: "6.4",
                    compilerBuildIdentifier: "swiftlang-6.4.0.27.1",
                    toolchainIdentifier: "com.apple.dt.toolchain.XcodeDefault"
                ),
                buildConfiguration: CompilerBuildConfiguration(
                    configurationName: "debug-feature-a",
                    moduleName: "main",
                    targetTriple: "arm64-apple-macosx27.2.0",
                    sdkIdentifier: "macosx27.2",
                    swiftLanguageVersion: "6",
                    compilationConditions: ["FEATURE_A", "DEBUG", "FEATURE_A"],
                    fingerprint: try CompilerEvidenceDigest(
                        value: "1111111111111111111111111111111111111111111111111111111111111111"
                    )
                ),
                sourceRevision: .versionControl(
                    revision: try CompilerRevisionIdentifier("0123456789abcdef0123456789abcdef01234567"),
                    workingTreeState: .modified,
                    contentDigest: try CompilerEvidenceDigest(
                        value: "2222222222222222222222222222222222222222222222222222222222222222"
                    )
                )
            ),
            availability: CompilerEvidenceAvailabilitySet(
                typeChecking: .available,
                conditionalCompilation: .available,
                macroExpansion: .unavailable(unavailable),
                nameBinding: .ambiguous(ambiguous),
                dispatchTargets: .unavailable(
                    CompilerEvidenceIssue(
                        code: "not-implemented",
                        message: "Dispatch evidence is outside schema 1's implemented providers."
                    )
                )
            )
        )
    }

    private func renderJSON(_ report: CompilerEvidenceReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
    }

    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CompilerEvidence")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
