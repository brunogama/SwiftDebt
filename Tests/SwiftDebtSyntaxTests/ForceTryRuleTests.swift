import Foundation
import Testing

@testable import SwiftDebtCore
@testable import SwiftDebtSyntax

/// Verifies `errors.force-try` (TASK-001, research #28, addendum J): a
/// deterministic `.syntax`-scope rule that detects `try!` expressions and
/// never fires on plain `try` or `try?`.
@Suite("errors.force-try")
struct ForceTryRuleTests {
    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = root.appendingPathComponent("Fixtures/ForceTry/\(name).swift.txt")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("identity, scope, mode, and evidence contract match the catalog claim")
    func definitionShape() {
        let rule = ForceTryRule()
        #expect(rule.definition.identity == RuleIdentity("errors.force-try"))
        #expect(rule.definition.scope == .syntax)
        #expect(rule.definition.mode == .deterministic)
        #expect(rule.definition.requirements.capabilities == [.syntax])
        #expect(rule.definition.metadata.supportState == .supported)
        #expect(
            rule.definition.evidenceContract.required
                == .fact(EvidenceRequirement(key: "forceTryExpression", kind: .syntax))
        )
    }

    @Test("positive fixture: two try! expressions are detected as complete")
    func positiveFixtureDetectsForceTry() throws {
        let source = try fixture("Positive")
        let outcome = try ForceTryRule().evaluate(path: "Positive.swift", source: source)

        #expect(outcome.state == .complete)
        #expect(outcome.detections.count == 3)

        let lines = outcome.detections.map(\.location.line).sorted()
        #expect(lines == [5, 10, 11])
        for detection in outcome.detections {
            #expect(detection.location.file == "Positive.swift")
        }
    }

    @Test("adversarial fixture: plain try and try? never fire")
    func adversarialFixtureDoesNotFire() throws {
        let source = try fixture("Adversarial")
        let outcome = try ForceTryRule().evaluate(path: "Adversarial.swift", source: source)

        #expect(outcome.state == .complete)
        #expect(outcome.detections.isEmpty)
    }
}
