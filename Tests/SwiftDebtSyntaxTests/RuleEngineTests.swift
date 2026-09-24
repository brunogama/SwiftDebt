import SwiftDebtCore
import Testing

@testable import SwiftDebtSyntax

@Suite("Rule engine transactions")
struct RuleEngineTests {
    @Test("Analysis snapshot groups selected source provenance and results")
    func analysisSnapshotProvenance() throws {
        let snapshot = try RuleEngine().analyze(
            [
                SourceUnit(path: "Sources/First.swift", content: "let first = try! read()"),
                SourceUnit(path: "Sources/Second.swift", content: "let second = try? read()"),
            ],
            using: ForceTryRule()
        )

        #expect(snapshot.selectedSourcePaths.map(\.rawValue) == ["Sources/First.swift", "Sources/Second.swift"])
        #expect(snapshot.ruleResults.count == 2)
        #expect(snapshot.isComplete)
        #expect(snapshot.detections.count == 1)
    }

    @Test("Force try reports only try! at the exclamation mark")
    func forceTryLocationsAndConditionalBranches() throws {
        let source = SourceUnit(
            path: "Sources/Input.swift",
            content: """
                func load() throws {
                  _ = try? read()
                  _ = try! read()
                  try perform()
                #if FEATURE
                  _ = try! feature()
                #else
                  _ = try! fallback()
                #endif
                }
                """
        )

        let result = try RuleEngine().analyze(source, using: ForceTryRule())
        let detections = try committedDetections(result)

        #expect(detections.map(\.location.line) == [3, 6, 8])
        #expect(detections.map(\.location.column) == [10, 10, 10])
        #expect(detections.allSatisfy { $0.ruleIdentity == ForceTryRule.identity })
        #expect(detections.allSatisfy { $0.semanticRevision == .initial })
        #expect(detections.allSatisfy { $0.severity == .warning })
        #expect(
            detections.allSatisfy {
                $0.message == "This try! traps if the expression throws; handle or propagate the error."
            }
        )
        #expect(ForceTryRule.contract.semantics.contains("all #if branches"))
    }

    @Test("A clean committed execution alone proves absence")
    func cleanExecutionProvesAbsence() throws {
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Input.swift", content: "let value = try? read()"),
            using: ForceTryRule()
        )

        #expect(result.isCommitted)
        #expect(result.provesAbsence)
        #expect(result.detections.isEmpty)
    }

    @Test("Parse failure does not execute the rule")
    func parseFailureSkipsRule() throws {
        let recorder = InvocationRecorder()
        let snapshot = try RuleEngine().analyze(
            [SourceUnit(path: "Broken.swift", content: "func broken( {")],
            using: RecordingRule(recorder: recorder)
        )
        let result = try #require(snapshot.ruleResults.first)

        guard case .parseFailed(let diagnostics) = result.outcome else {
            Issue.record("Expected parseFailed, got \(result.outcome)")
            return
        }
        #expect(recorder.invocations == 0)
        #expect(!diagnostics.isEmpty)
        #expect(!snapshot.isComplete)
        #expect(snapshot.detections.isEmpty)
        #expect(!result.provesAbsence)
    }

    @Test("Unsupported execution is distinct and discards valid partial emissions")
    func unsupportedDiscardsPartialEmission() throws {
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Input.swift", content: "let value = 1"),
            using: UnsupportedAfterEmissionRule()
        )

        #expect(result.outcome == .unsupported(reason: "requires compiler facts"))
        #expect(result.detections.isEmpty)
        #expect(!result.provesAbsence)
    }

    @Test("A thrown rule discards valid partial emissions")
    func thrownRuleDiscardsPartialEmission() throws {
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Input.swift", content: "let value = 1"),
            using: ThrowAfterEmissionRule()
        )

        guard case .failed(let reason) = result.outcome else {
            Issue.record("Expected failed, got \(result.outcome)")
            return
        }
        #expect(reason.contains("rule threw: deliberate"))
        #expect(result.detections.isEmpty)
        #expect(!result.provesAbsence)
    }

    @Test("An invalid emission poisons the transaction")
    func invalidEmissionCannotBecomeUnsupported() throws {
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Input.swift", content: "let value = 1"),
            using: InvalidThenUnsupportedRule()
        )

        guard case .failed(let reason) = result.outcome else {
            Issue.record("Expected failed, got \(result.outcome)")
            return
        }
        #expect(reason.contains("invalid emission"))
        #expect(reason.contains("message must be a nonempty single line"))
        #expect(result.detections.isEmpty)
    }

    @Test("A node from another syntax tree fails the transaction")
    func foreignNodeFailsTransaction() throws {
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Input.swift", content: "let value = 1"),
            using: ForeignNodeRule()
        )

        guard case .failed(let reason) = result.outcome else {
            Issue.record("Expected failed, got \(result.outcome)")
            return
        }
        #expect(reason.contains("node does not belong to the current source tree"))
        #expect(result.detections.isEmpty)
    }

    @Test("An escaped emitter is inert after detect returns")
    func escapedEmitterIsInert() throws {
        let escape = EscapedEmission()
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Input.swift", content: "let value = 1"),
            using: EscapingRule(escape: escape)
        )

        #expect(result.provesAbsence)
        escape.emit?()
        #expect(result.provesAbsence)
        #expect(result.detections.isEmpty)
    }

    @Test("Analysis context exposes the normalized relative source path")
    func contextSourcePathIsNormalized() throws {
        let recorder = SourcePathRecorder()
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Sources/Feature/../Feature//Input.swift", content: "let value = 1"),
            using: SourcePathRecordingRule(recorder: recorder)
        )

        #expect(recorder.path?.rawValue == "Sources/Feature/Input.swift")
        #expect(result.sourcePath.rawValue == "Sources/Feature/Input.swift")
        #expect(result.provesAbsence)
    }
}
