import Testing

@testable import SwiftDebtCore

@Suite("Capability resolution engine")
struct CapabilityResolutionEngineTests {
    private func rule(
        _ id: String, requiring capabilities: Set<AnalysisCapability>
    ) -> RuleDefinition {
        RuleDefinition(
            identity: RuleIdentity(id),
            metadata: RuleMetadata(
                title: id,
                category: .style,
                provenance: [],
                supportState: .research
            ),
            scope: .syntax,
            mode: .deterministic,
            requirements: RuleRequirements(capabilities),
            evidenceContract: EvidenceContract(
                required: .fact(EvidenceRequirement(key: "any", kind: .syntax))
            ),
            semanticRevision: 1
        )
    }

    @Test func syntaxOnlyRuleClosureIsExactlySyntax() {
        let syntaxOnly = rule("syntax-only", requiring: [.syntax])

        let resolution = CapabilityResolutionEngine().resolve(enabledRules: [syntaxOnly])

        #expect(resolution.capabilities == [.syntax])
        #expect(resolution.rules(requiring: .syntax) == [RuleIdentity("syntax-only")])
    }

    /// FR-6 ("avoid unrelated work"): a syntax-only configuration must never
    /// initialize the isolation subsystem, and adding a rule that needs
    /// `.isolation` must pull in exactly the dependency chain
    /// `.isolation` declares - `.syntax`, `.symbols`, `.types` - nothing more.
    @Test func addingIsolationRulePullsInExactlyItsDependencyChain() {
        let syntaxOnly = rule("syntax-only", requiring: [.syntax])
        let isolationRule = rule("isolation-rule", requiring: [.isolation])

        let syntaxOnlyResolution = CapabilityResolutionEngine().resolve(enabledRules: [syntaxOnly])
        let bothResolution = CapabilityResolutionEngine().resolve(
            enabledRules: [syntaxOnly, isolationRule])

        let addedByIsolationRule = bothResolution.capabilities.subtracting(
            syntaxOnlyResolution.capabilities)
        #expect(addedByIsolationRule == [.isolation, .symbols, .types])
        #expect(bothResolution.capabilities == [.syntax, .symbols, .types, .isolation])

        // Every capability the isolation rule needed - including the two it
        // only reached by following dependency edges - traces back to it.
        #expect(bothResolution.rules(requiring: .isolation) == [RuleIdentity("isolation-rule")])
        #expect(bothResolution.rules(requiring: .symbols) == [RuleIdentity("isolation-rule")])
        #expect(bothResolution.rules(requiring: .types) == [RuleIdentity("isolation-rule")])
        // .syntax is shared: both rules require it.
        let expectedSyntaxContributors: Set<RuleIdentity> = [
            RuleIdentity("syntax-only"), RuleIdentity("isolation-rule"),
        ]
        #expect(bothResolution.rules(requiring: .syntax) == expectedSyntaxContributors)
    }

    /// FR-6 ("removing the last consumer removes that work"): dropping the
    /// isolation rule from the enabled set must remove `.isolation`,
    /// `.symbols`, and `.types` from the closure again, since no remaining
    /// rule needs them.
    @Test func removingTheLastConsumerRemovesItsCapabilities() {
        let syntaxOnly = rule("syntax-only", requiring: [.syntax])
        let isolationRule = rule("isolation-rule", requiring: [.isolation])

        let withIsolationRule = CapabilityResolutionEngine().resolve(
            enabledRules: [syntaxOnly, isolationRule])
        #expect(withIsolationRule.isNeeded(.isolation))
        #expect(withIsolationRule.isNeeded(.symbols))
        #expect(withIsolationRule.isNeeded(.types))

        let afterRemoval = CapabilityResolutionEngine().resolve(enabledRules: [syntaxOnly])

        #expect(!afterRemoval.isNeeded(.isolation))
        #expect(!afterRemoval.isNeeded(.symbols))
        #expect(!afterRemoval.isNeeded(.types))
        #expect(afterRemoval.rules(requiring: .isolation).isEmpty)
        #expect(afterRemoval.capabilities == [.syntax])
    }

    @Test func sharedDependencyKeepsMultipleContributors() {
        let ownershipRule = rule("ownership-rule", requiring: [.ownership])
        let controlFlowRule = rule("control-flow-rule", requiring: [.controlFlow])

        let resolution = CapabilityResolutionEngine().resolve(
            enabledRules: [ownershipRule, controlFlowRule])

        // Both .ownership and .controlFlow depend on [.syntax, .symbols], so
        // .symbols must be traceable to both, even though neither rule
        // declared .symbols directly.
        let expectedContributors: Set<RuleIdentity> = [
            RuleIdentity("ownership-rule"), RuleIdentity("control-flow-rule"),
        ]
        #expect(resolution.rules(requiring: .symbols) == expectedContributors)
    }

    @Test func emptyEnabledSetResolvesToEmptyClosure() {
        let resolution = CapabilityResolutionEngine().resolve(enabledRules: [RuleDefinition]())

        #expect(resolution.capabilities.isEmpty)
        #expect(resolution.rules(requiring: .syntax).isEmpty)
    }
}
