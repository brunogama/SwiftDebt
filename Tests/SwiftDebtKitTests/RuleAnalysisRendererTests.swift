import SwiftDebtCore
import Testing

@testable import SwiftDebtReporting

@Suite("Rule observation text rendering")
struct RuleAnalysisRendererTests {
    @Test("Unavailable outcomes remain distinct and render on one line")
    func unavailableOutcomesAreSanitized() throws {
        let descriptor = try makeDescriptor()
        let unsupportedPath = try SourcePath("Sources/Unsupported.swift")
        let failedPath = try SourcePath("Sources/Failed.swift")
        let snapshot = AnalysisSnapshot(
            ruleDescriptors: [descriptor],
            selectedSourcePaths: [unsupportedPath, failedPath],
            ruleResults: [
                RuleAnalysisResult(
                    descriptor: descriptor,
                    sourcePath: unsupportedPath,
                    outcome: .unsupported(reason: "requires compiler facts")
                ),
                RuleAnalysisResult(
                    descriptor: descriptor,
                    sourcePath: failedPath,
                    outcome: .failed(reason: "rule threw: boom\nforged line")
                ),
            ]
        )

        let output = RuleAnalysisRenderer().render(snapshot)

        #expect(output.contains("Sources/Unsupported.swift: unsupported: requires compiler facts"))
        #expect(output.contains("Sources/Failed.swift: failed: rule threw: boom forged line"))
        #expect(!output.contains("\nforged line"))
        #expect(output.contains("Status: INCOMPLETE"))
        #expect(output.contains("Absence was not established for incomplete rule executions."))
        #expect(!output.contains("No detections in committed rule executions."))
    }

    private func makeDescriptor() throws -> RuleDescriptor {
        RuleDescriptor(
            identity: RuleIdentity(
                namespace: try #require(RuleNamespace("swiftdebt")),
                id: try #require(RuleID("force-try"))
            ),
            metadata: RuleMetadata(
                name: "Force try",
                defaultSeverity: .warning,
                remediation: "Handle the error."
            ),
            contract: RuleContract(
                semanticRevision: .initial,
                semantics: "Reports try!.",
                rationale: "try! can trap."
            )
        )
    }
}
