import Testing

@testable import SwiftDebtCore

@Suite("Rule Catalog boundary contracts")
struct RuleCatalogBoundaryCoverageTests {
    @Test("Advanced capabilities declare their immediate prerequisites")
    func advancedCapabilityDependenciesAreStable() {
        let expectations: [(AnalysisCapability, Set<AnalysisCapability>)] = [
            (.dataFlow, [.syntax, .symbols, .controlFlow]),
            (.moduleGraph, [.symbols, .references]),
            (.dependencyGraph, [.symbols, .references]),
            (.callGraph, [.symbols, .references, .controlFlow]),
            (.packageManifest, [.buildConfiguration]),
            (.xcodeProject, [.buildConfiguration]),
            (.semanticSimilarity, [.syntax, .symbols]),
        ]

        for (capability, expectedDependencies) in expectations {
            #expect(capability.directDependencies == expectedDependencies)
        }
    }

    @Test("Minimal YAML preserves bare sequence items and unquotes scalar styles")
    func minimalYAMLHandlesSupportedScalarBoundaries() throws {
        let node = try MinimalYAMLParser.parse(
            """
            -
              child: "double quoted"
            -
            - 'single quoted'
            """)

        guard case .sequence(let items) = node else {
            Issue.record("expected a top-level sequence")
            return
        }
        #expect(items.count == 3)
        #expect(items[0]["child"]?.stringValue == "double quoted")
        #expect(items[1].stringValue?.isEmpty == true)
        #expect(items[2].stringValue == "single quoted")
    }

    @Test("An empty mapping value does not consume its following sibling")
    func emptyMappingPreservesSibling() throws {
        let node = try MinimalYAMLParser.parse("empty:\nnext: value")
        guard case .mapping(let emptyPairs) = node["empty"] else {
            Issue.record("expected an empty mapping")
            return
        }
        #expect(emptyPairs.isEmpty)
        #expect(node["next"]?.stringValue == "value")
    }

    @Test("A mapping line without a separator reports the original line")
    func malformedMappingLineIsActionable() {
        #expect(
            throws: RuleManifestError.malformedDocument(
                reason: "expected 'key: value' in line 'missing separator'")
        ) {
            try MinimalYAMLParser.parse("missing separator")
        }
    }

    @Test(
        "Malformed manifests report the violated structural contract",
        arguments: malformedManifestCases
    )
    func malformedManifestsAreActionable(testCase: MalformedManifestCase) {
        let (definitions, errors) = RuleManifestParser.collectErrors(yaml: testCase.yaml)

        #expect(definitions.isEmpty)
        #expect(errors.count == 1)
        guard let error = errors.first else { return }
        guard case .malformedDocument(let reason) = error else {
            Issue.record("expected malformedDocument, got \(error)")
            return
        }
        #expect(reason.contains(testCase.expectedReason))
        #expect(error.description.contains(testCase.expectedReason))
    }

    @Test("Any predicates retain every alternative")
    func anyPredicateRetainsAlternatives() throws {
        let anyEvidence = """
                evidence:
                  required:
                    any:
                      - fact:
                          key: firstSyntaxNode
                          kind: syntax
                      - fact:
                          key: secondSyntaxNode
                          kind: syntax
            """
        let yaml = boundaryManifestReplacing(boundaryEvidenceBlock, with: anyEvidence)
        let definition = try #require(RuleManifestParser.parse(yaml: yaml).first)

        let first = EvidenceRequirement(key: "firstSyntaxNode", kind: .syntax)
        let second = EvidenceRequirement(key: "secondSyntaxNode", kind: .syntax)
        #expect(definition.evidenceContract.required == .any([.fact(first), .fact(second)]))
    }

    @Test("Omitted capabilities cannot satisfy a fact requirement")
    func omittedCapabilitiesRemainEmpty() {
        let yaml = boundaryManifestReplacing("    requirements:\n      - syntax\n")
        let expected = RuleManifestError.incompatibleEvidenceMetadata(
            ruleID: "boundary.rule",
            reason: "fact 'syntaxNode' has kind 'syntax' which requires capability "
                + "'syntax', not present in requirements")
        #expect(throws: expected) {
            try RuleManifestParser.parse(yaml: yaml)
        }
    }

    @Test("Any predicates require at least one alternative")
    func emptyAnyPredicateIsRejected() {
        let emptyAnyEvidence = """
                evidence:
                  required:
                    any: []
            """
        let yaml = boundaryManifestReplacing(boundaryEvidenceBlock, with: emptyAnyEvidence)
        let expected = RuleManifestError.invalidEvidenceShape(
            ruleID: "boundary.rule", reason: "'any' predicate is empty")

        #expect(throws: expected) {
            try RuleManifestParser.parse(yaml: yaml)
        }
    }

    @Test("External runtime support requires a runtime or external detection mode")
    func externalRuntimeMaturityRejectsStaticDetection() {
        let yaml = boundaryManifestReplacing(
            "supportState: supported", with: "supportState: externalRuntimeRequired")
        let expected = RuleManifestError.inconsistentMaturity(
            ruleID: "boundary.rule",
            reason: "supportState 'externalRuntimeRequired' requires detectionMode "
                + "'runtimeDependent' or 'external', found 'deterministic'")

        #expect(throws: expected) {
            try RuleManifestParser.parse(yaml: yaml)
        }
    }

    @Test("Manifest diagnostics identify the rule and violated contract")
    func manifestErrorDescriptionsAreActionable() {
        let diagnostics: [(RuleManifestError, String)] = [
            (
                .invalidEvidenceShape(ruleID: "rule.one", reason: "empty any"),
                "rule catalog manifest error: rule 'rule.one' has an invalid evidence shape: "
                    + "empty any"
            ),
            (
                .inconsistentMaturity(ruleID: "rule.two", reason: "mode mismatch"),
                "rule catalog manifest error: rule 'rule.two' has inconsistent maturity metadata: "
                    + "mode mismatch"
            ),
            (
                .incompatibleEvidenceMetadata(ruleID: "rule.three", reason: "missing symbols"),
                "rule catalog manifest error: rule 'rule.three' has incompatible evidence "
                    + "metadata: "
                    + "missing symbols"
            ),
            (
                .malformedDocument(reason: "rules must be a sequence"),
                "rule catalog manifest error: malformed manifest document: rules must be a sequence"
            ),
        ]

        for (error, expectedDescription) in diagnostics {
            #expect(error.description == expectedDescription)
        }
    }

    @Test("Failed observation retains its diagnostic and cannot prove absence")
    func failedObservationRetainsDiagnostic() {
        let state = ObservationState.failed(RuleAnalysisFailure(message: "sensor timed out"))

        guard case .failed(let failure) = state else {
            Issue.record("expected a failed observation")
            return
        }
        #expect(failure.message == "sensor timed out")
        #expect(state.provesAbsenceWhenNoDetection == false)
    }

    @Test("Identity and revision values preserve their public representations")
    func identityAndRevisionRepresentationsAreStable() {
        let identity = RuleIdentity("errors.force-try")
        let implementationValue: Int = 7
        let evidenceValue: Int = 11
        let implementation = ImplementationRevision(implementationValue)
        let explicitEvidence = EvidenceRevision(evidenceValue)
        let literalEvidence: EvidenceRevision = 12

        #expect(identity.description == "errors.force-try")
        #expect(implementation.value == 7)
        #expect(explicitEvidence.value == 11)
        #expect(literalEvidence.value == 12)
    }
}
