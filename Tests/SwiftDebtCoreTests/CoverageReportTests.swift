import Testing

@testable import SwiftDebtCore

/// Exercises `CoverageReport` (PRD FR-18) and the `RuleIdentity`-based rule
/// inspection accessor (PRD FR-19) against a small hand-built catalog.
@Suite("Coverage report")
struct CoverageReportTests {
    private static func rule(
        id: String, category: RuleCategory, scope: RuleScope, mode: DetectionMode,
        supportState: SupportState
    ) -> RuleDefinition {
        RuleDefinition(
            identity: RuleIdentity(id),
            metadata: RuleMetadata(
                title: id, category: category, provenance: [RuleProvenance(researchItem: 1)],
                supportState: supportState
            ),
            scope: scope,
            mode: mode,
            requirements: RuleRequirements([.syntax]),
            evidenceContract: EvidenceContract(
                required: .fact(EvidenceRequirement(key: "k", kind: .syntax))
            ),
            semanticRevision: 1
        )
    }

    @Test("Groups a catalog by Support State, category, scope, and Detection Mode")
    func groupsCatalogAlongAllFourAxes() {
        let catalog = [
            Self.rule(
                id: "a", category: .concurrency, scope: .syntax, mode: .deterministic,
                supportState: .supported),
            Self.rule(
                id: "b", category: .concurrency, scope: .repository, mode: .heuristic,
                supportState: .partial),
            Self.rule(
                id: "c", category: .memory, scope: .syntax, mode: .deterministic,
                supportState: .supported),
        ]
        let report = CoverageReport(rules: catalog)

        #expect(report.totalRuleCount == 3)
        #expect(report.count(for: SupportState.supported) == 2)
        #expect(report.count(for: SupportState.partial) == 1)
        #expect(report.count(for: SupportState.research) == 0)
        #expect(report.count(for: RuleCategory.concurrency) == 2)
        #expect(report.count(for: RuleCategory.memory) == 1)
        #expect(report.count(for: RuleScope.syntax) == 2)
        #expect(report.count(for: RuleScope.repository) == 1)
        #expect(report.count(for: DetectionMode.deterministic) == 2)
        #expect(report.count(for: DetectionMode.heuristic) == 1)

        // Zero-count axes are represented, not omitted.
        #expect(report.supportStateCounts[.notReliablyObservable] == 0)
        #expect(report.scopeCounts.count == RuleScope.allCases.count)
        #expect(report.detectionModeCounts.count == DetectionMode.allCases.count)
        #expect(report.categoryCounts.count == RuleCategory.allCases.count)
    }

    @Test("Rule inspection returns the full RuleDefinition by RuleIdentity (FR-19)")
    func inspectsRuleByIdentity() {
        let target = Self.rule(
            id: "target.rule", category: .testing, scope: .project, mode: .derived,
            supportState: .research)
        let catalog = [target]

        let found = catalog.ruleDefinition(for: RuleIdentity("target.rule"))
        #expect(found?.metadata.title == "target.rule")
        #expect(found?.metadata.provenance.first?.researchItem == 1)
        #expect(found?.evidenceContract == target.evidenceContract)
        #expect(found?.semanticRevision == target.semanticRevision)
        #expect(catalog.ruleDefinition(for: RuleIdentity("missing")) == nil)
    }
}
