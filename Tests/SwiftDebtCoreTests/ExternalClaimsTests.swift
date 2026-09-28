import Testing

@testable import SwiftDebtCore

/// TASK-008: a cataloged claim with `supportState: .externalRuntimeRequired`
/// and no `RuleImplementation` at all (Invariant Q2, PRD FR-1/FR-3). These
/// tests confirm the catalog machinery treats "no implementation exists"
/// as an ordinary, accepted state rather than something to reject or paper
/// over - and they stop at that: there is no `RuleImplementation` here, so
/// there are no Detections to check, and nothing below fabricates one.
@Suite("External runtime-required claim with no implementation")
struct ExternalClaimsTests {

    @Test("The cataloged definition itself is externalRuntimeRequired/.external, unimplemented")
    func definitionIsCatalogedWithNoImplementation() {
        let definition = ExternalClaims.ciToolchainNotPinned

        #expect(definition.metadata.supportState == .externalRuntimeRequired)
        #expect(definition.mode == .external)
        #expect(definition.metadata.category == .ci)
        #expect(definition.metadata.provenance.first?.researchItem == 88)
        // No RuleImplementation type exists for this identity anywhere in
        // the module; the definition's existence does not depend on one
        // (that is the whole point of Invariant Q2/FR-3).
    }

    @Test("RuleCatalogValidator accepts a zero-implementation manifest entry (FR-20)")
    func validatorAcceptsEntryWithNoImplementation() throws {
        let yaml = """
            rules:
              - id: ci.toolchain-not-pinned
                semanticRevision: 1
                title: CI pipeline lacks deterministic toolchain pinning
                category: ci
                scope: external
                detectionMode: external
                requirements:
                  - buildConfiguration
                evidence:
                  required:
                    fact:
                      key: ciRunnerToolchainResolution
                      kind: configuration
                supportState: externalRuntimeRequired
                provenance:
                  researchItem: 88
                  note: addendum J - CI/CD claims research #86-92
            """

        let definitions = try RuleManifestParser.parse(yaml: yaml)

        #expect(definitions.count == 1)
        let definition = try #require(definitions.first)
        #expect(definition.identity == RuleIdentity("ci.toolchain-not-pinned"))
        #expect(definition.metadata.supportState == .externalRuntimeRequired)
        #expect(definition.mode == .external)
        // The validator's job is entry-shape and cross-field consistency; it
        // has no notion of "implementation count" at all, and this manifest
        // entry names no implementation. It still validates cleanly.
    }

    @Test("CoverageReport groups the unimplemented entry under externalRuntimeRequired (FR-18)")
    func coverageReportGroupsUnimplementedEntry() {
        let catalog = [ExternalClaims.ciToolchainNotPinned]
        let report = CoverageReport(rules: catalog)

        let externalGroup = report.bySupportState[.externalRuntimeRequired]
        #expect(externalGroup?.count == 1)
        #expect(externalGroup?.first?.identity == ExternalClaims.ciToolchainNotPinned.identity)
        #expect(report.count(for: SupportState.externalRuntimeRequired) == 1)
        #expect(report.count(for: DetectionMode.external) == 1)

        let found = catalog.ruleDefinition(for: RuleIdentity("ci.toolchain-not-pinned"))
        #expect(found != nil)
    }
}
