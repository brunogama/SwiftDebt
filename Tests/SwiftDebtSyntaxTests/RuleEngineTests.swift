import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtSyntax

@Suite("Rule engine transactions")
struct RuleEngineTests {
    @Test("Structural digest uses canonical SHA-256")
    func structuralSHA256() {
        #expect(
            StructuralSHA256.hexDigest(Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

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
        #expect(snapshot.ruleDescriptors.map(\.identity) == [ForceTryRule.identity])
        #expect(snapshot.ruleResults.count == 2)
        #expect(snapshot.isComplete)
        #expect(snapshot.detections.count == 1)

        let missingResult = AnalysisSnapshot(
            ruleDescriptors: snapshot.ruleDescriptors,
            selectedSourcePaths: snapshot.selectedSourcePaths,
            ruleResults: []
        )
        #expect(!missingResult.isComplete)
    }

    @Test("Multiple rules preserve independent atomic outcomes")
    func multipleRuleTransactions() throws {
        let snapshot = try RuleEngine().analyze(
            [SourceUnit(path: "Input.swift", content: "let value = try! read()")],
            using: [
                ForceTryRule(), UnsupportedAfterEmissionRule(), ThrowAfterEmissionRule(),
                InvalidThenUnsupportedRule(),
            ]
        )

        #expect(
            snapshot.ruleDescriptors.map(\.identity) == [
                ForceTryRule.identity, UnsupportedAfterEmissionRule.identity,
                ThrowAfterEmissionRule.identity, InvalidThenUnsupportedRule.identity,
            ]
        )
        #expect(snapshot.ruleResults.count == 4)
        #expect(snapshot.ruleResults[0].isCommitted)
        #expect(snapshot.ruleResults[0].detections.count == 1)
        #expect(snapshot.ruleResults[1].outcome == .unsupported(reason: "requires compiler facts"))
        guard case .failed(let thrownReason) = snapshot.ruleResults[2].outcome else {
            Issue.record("Expected thrown rule to fail")
            return
        }
        guard case .failed(let invalidReason) = snapshot.ruleResults[3].outcome else {
            Issue.record("Expected invalid emission to fail")
            return
        }
        #expect(thrownReason.contains("rule threw: deliberate"))
        #expect(invalidReason.contains("invalid emission"))
        #expect(snapshot.detections.count == 1)
        #expect(!snapshot.isComplete)
    }

    @Test("Rule and normalized source identities must be unique")
    func duplicateSelectionIsRejected() throws {
        #expect(throws: RuleEngineError.noRulesSelected) {
            try RuleEngine().analyze([SourceUnit(path: "Input.swift", content: "let value = 1")], using: [])
        }
        #expect(throws: RuleEngineError.duplicateRuleIdentity(ForceTryRule.identity)) {
            try RuleEngine().analyze(
                [SourceUnit(path: "Input.swift", content: "let value = 1")],
                using: [ForceTryRule(), ForceTryRule()]
            )
        }
        let duplicatePath = try SourcePath("Sources/Input.swift")
        #expect(throws: RuleEngineError.duplicateSourcePath(duplicatePath)) {
            try RuleEngine().analyze(
                [
                    SourceUnit(path: "Sources//Input.swift", content: "let first = 1"),
                    SourceUnit(path: "Sources/Input.swift", content: "let second = 2"),
                ],
                using: [ForceTryRule()]
            )
        }
        #expect(RuleEngineError.noRulesSelected.description == "At least one debt rule must be selected.")
        #expect(
            RuleEngineError.duplicateRuleIdentity(ForceTryRule.identity).description
                == "Duplicate rule identity: swiftdebt.force-try"
        )
        #expect(
            RuleEngineError.duplicateSourcePath(duplicatePath).description
                == "Duplicate normalized source path: Sources/Input.swift"
        )
    }

    @Test("RuleEngine rejects compatibility that does not point forward")
    func invalidSemanticCompatibilityIsRejectedAtRegistration() {
        let expected = RuleEngineError.invalidCompatibilityDeclaration(
            InvalidCompatibilityDirectionRule.identity,
            "a declaration must point from an earlier revision into the current revision."
        )

        #expect(throws: expected) {
            try RuleEngine().analyze(
                [SourceUnit(path: "Input.swift", content: "let value = 1")],
                using: InvalidCompatibilityDirectionRule()
            )
        }
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

    @Test("Structural evidence ignores trivia and distinguishes subject and declaration edits")
    func structuralContinuityEvidence() throws {
        let original = try forceTryDetection(
            """
            func load() throws -> Int { 1 }
            func reload() throws -> Int { 2 }
            func run() {
                _ = try! load()
            }
            """
        )
        let shifted = try forceTryDetection(
            """
            func load() throws -> Int { 1 }
            func reload() throws -> Int { 2 }

            // Trivia and absolute location do not define continuity.
            func run() {
                _ = try! load()
            }
            """
        )
        let editedSubject = try forceTryDetection(
            """
            func load() throws -> Int { 1 }
            func reload() throws -> Int { 2 }
            func run() {
                _ = try! reload()
            }
            """
        )
        let differentDeclaration = try forceTryDetection(
            """
            func load() throws -> Int { 1 }
            func reload() throws -> Int { 2 }
            func replacement() {
                _ = try! reload()
            }
            """
        )

        #expect(original.structuralEvidence == shifted.structuralEvidence)
        #expect(original.location != shifted.location)
        #expect(
            original.structuralEvidence.subjectDigest
                != editedSubject.structuralEvidence.subjectDigest
        )
        #expect(
            original.structuralEvidence.enclosingDeclarationDigest
                == editedSubject.structuralEvidence.enclosingDeclarationDigest
        )
        #expect(
            editedSubject.structuralEvidence.subjectDigest
                == differentDeclaration.structuralEvidence.subjectDigest
        )
        #expect(
            editedSubject.structuralEvidence.enclosingDeclarationDigest
                != differentDeclaration.structuralEvidence.enclosingDeclarationDigest
        )
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

        let multipleRules = try RuleEngine().analyze(
            [SourceUnit(path: "Broken.swift", content: "func broken( {")],
            using: [RecordingRule(recorder: recorder), UnsupportedAfterEmissionRule()]
        )
        #expect(recorder.invocations == 0)
        #expect(multipleRules.ruleResults.count == 2)
        #expect(
            multipleRules.ruleResults.allSatisfy {
                if case .parseFailed = $0.outcome { return true }
                return false
            }
        )
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

    private func forceTryDetection(_ content: String) throws -> Detection {
        let result = try RuleEngine().analyze(
            SourceUnit(path: "Sources/Input.swift", content: content),
            using: ForceTryRule()
        )
        return try #require(committedDetections(result).first)
    }
}
