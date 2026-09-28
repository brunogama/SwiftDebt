import Foundation
import Testing

@testable import SwiftDebtCore

@Suite("Rule Catalog Manifest parsing and validation")
struct RuleManifestParserTests {

    // MARK: - Positive fixtures

    @Test func validManifestDecodesBothRules() throws {
        let definitions = try RuleManifestParser.parse(yaml: fixture("valid.yaml"))

        #expect(definitions.count == 2)

        let reentrancyID = "concurrency.actor-reentrancy"
        let reentrancy = try #require(definitions.first { $0.identity.rawValue == reentrancyID })
        #expect(reentrancy.metadata.title == "Actor reentrancy after suspension")
        #expect(reentrancy.metadata.category == .concurrency)
        #expect(reentrancy.metadata.supportState == .partial)
        #expect(reentrancy.scope == .sourceUnit)
        #expect(reentrancy.mode == .derived)
        #expect(reentrancy.semanticRevision == SemanticRevision(1))
        let expectedCapabilities: Set<AnalysisCapability> = [
            .syntax, .isolation, .controlFlow, .references,
        ]
        #expect(reentrancy.requirements.capabilities == expectedCapabilities)
        #expect(reentrancy.metadata.provenance == [RuleProvenance(researchItem: 19)])

        try assertReentrancyEvidenceShape(reentrancy.evidenceContract.required)

        let forceTryID = "errors.force-try"
        let forceTry = try #require(definitions.first { $0.identity.rawValue == forceTryID })
        #expect(forceTry.metadata.provenance.first?.note?.contains("try!") == true)
        #expect(forceTry.evidenceContract.optional.count == 1)
    }

    private func assertReentrancyEvidenceShape(_ predicate: EvidencePredicate) throws {
        guard case .all(let children) = predicate else {
            Issue.record("expected an 'all' predicate at the root of the required evidence")
            return
        }
        #expect(children.count == 4)
        guard case .fact(let requirement) = children[0] else {
            Issue.record("expected the first child to be a fact")
            return
        }
        #expect(requirement == EvidenceRequirement(key: "invariantEstablished", kind: .controlFlow))
        guard case .not(let negated) = children[3] else {
            Issue.record("expected the fourth child to be a negation")
            return
        }
        guard case .fact(let negatedFact) = negated else {
            Issue.record("expected the negated node to be a fact")
            return
        }
        #expect(negatedFact.key == "sufficientRevalidation")
    }

    // MARK: - FR-20 adversarial fixtures

    @Test func rejectsDuplicateIdentity() {
        #expect(throws: RuleManifestError.duplicateIdentity(id: "errors.force-try")) {
            try RuleManifestParser.parse(yaml: fixture("duplicate-id.yaml"))
        }
    }

    @Test func rejectsUnknownCapabilityReference() {
        let expected = RuleManifestError.unknownCapability(
            ruleID: "errors.force-try", value: "telepathy")
        #expect(throws: expected) {
            try RuleManifestParser.parse(yaml: fixture("unknown-capability.yaml"))
        }
    }

    @Test func rejectsEmptyAllPredicate() {
        do {
            _ = try RuleManifestParser.parse(yaml: fixture("empty-all.yaml"))
            Issue.record("expected an invalidEvidenceShape error")
        } catch RuleManifestError.invalidEvidenceShape(let ruleID, let reason) {
            #expect(ruleID == "errors.force-try")
            #expect(reason.contains("empty"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func rejectsInvalidEvidenceFactKind() {
        do {
            _ = try RuleManifestParser.parse(yaml: fixture("invalid-fact-kind.yaml"))
            Issue.record("expected an invalidEvidenceShape error")
        } catch RuleManifestError.invalidEvidenceShape(let ruleID, let reason) {
            #expect(ruleID == "errors.force-try")
            #expect(reason.contains("telepathic"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func rejectsMissingProvenance() {
        #expect(throws: RuleManifestError.missingProvenance(ruleID: "errors.force-try")) {
            try RuleManifestParser.parse(yaml: fixture("missing-provenance.yaml"))
        }
    }

    @Test func rejectsInconsistentMaturity() {
        do {
            _ = try RuleManifestParser.parse(yaml: fixture("inconsistent-maturity.yaml"))
            Issue.record("expected an inconsistentMaturity error")
        } catch RuleManifestError.inconsistentMaturity(let ruleID, let reason) {
            #expect(ruleID == "architecture.impossible-claim")
            #expect(reason.contains("notReliablyObservable"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func rejectsIncompatibleEvidenceMetadata() {
        do {
            _ = try RuleManifestParser.parse(yaml: fixture("incompatible-evidence-metadata.yaml"))
            Issue.record("expected an incompatibleEvidenceMetadata error")
        } catch RuleManifestError.incompatibleEvidenceMetadata(let ruleID, let reason) {
            #expect(ruleID == "concurrency.isolation-claim-without-capability")
            #expect(reason.contains("isolation"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func rejectsInvalidEnumRawValue() {
        let expected = RuleManifestError.invalidEnumValue(
            ruleID: "errors.force-try", field: "scope", value: "quantum")
        #expect(throws: expected) {
            try RuleManifestParser.parse(yaml: fixture("invalid-enum.yaml"))
        }
    }

    // MARK: - collectErrors

    @Test func collectErrorsReturnsEveryFailureInOnePass() {
        // "mixed-failures.yaml" combines a duplicate-id pair with an unknown
        // capability reference, so collectErrors must surface both without
        // stopping at the first.
        let mixedFailuresYAML = fixture("mixed-failures.yaml")
        let (definitions, errors) = RuleManifestParser.collectErrors(yaml: mixedFailuresYAML)
        #expect(definitions.count == 1)
        #expect(errors.contains(.duplicateIdentity(id: "errors.force-try")))
        let expectedCapabilityError = RuleManifestError.unknownCapability(
            ruleID: "errors.other-bad-rule", value: "telepathy")
        #expect(errors.contains(expectedCapabilityError))
    }

    @Test func malformedYAMLProducesAMalformedDocumentError() {
        let malformedYAML = "not: [valid, rule, catalog"
        let (definitions, errors) = RuleManifestParser.collectErrors(yaml: malformedYAML)
        #expect(definitions.isEmpty)
        #expect(errors.count == 1)
        guard case .malformedDocument = errors[0] else {
            Issue.record("expected a malformedDocument error, got \(errors[0])")
            return
        }
    }

    // MARK: - Helpers

    private func fixture(_ name: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RuleCatalogManifest")
            .appendingPathComponent(name)
        // swiftlint:disable:next force_try
        return try! String(contentsOf: url, encoding: .utf8)
    }
}
