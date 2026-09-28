import SwiftDebtCore
import SwiftDebtKit
import SwiftDebtSyntax
import Testing

@Suite("R2 acceptance corpus coverage (TASK-011)")
struct AcceptanceCorpusCoverageTests {
    private var corpus: [RuleDefinition] {
        [
            ForceTryRule().definition,
            BlockingSemaphoreInAsyncRule().definition,
            ActorReentrancyRule.definition,
            GlobalSharedDependencyRule.definition,
            ObservedObjectOwnedByViewRule.definition,
            UnsafeSwiftPMFlagsRule.definition,
            ExternalClaims.ciToolchainNotPinned,
        ]
    }

    @Test("SM-1: every corpus rule is traceable to a research item")
    func everyRuleHasProvenance() {
        for rule in corpus {
            #expect(!rule.metadata.provenance.isEmpty, "\(rule.identity) has no provenance")
            #expect(rule.metadata.provenance.allSatisfy { $0.researchItem > 0 })
        }
        let researchItems = Set(corpus.flatMap { $0.metadata.provenance.map(\.researchItem) })
        #expect(researchItems == [3, 12, 19, 28, 46, 71, 88])
    }

    @Test("SM-2: the reentrancy stub is the concrete honest-incompleteness proof")
    func reentrancyStubNeverClaimsSupported() {
        let stub = corpus.first { $0.identity == ActorReentrancyRule.definition.identity }
        #expect(stub?.metadata.supportState == .partial)
    }

    @Test("CoverageReport groups the real corpus by all four PRD FR-18 axes")
    func coverageReportGroupsRealCorpus() {
        let report = CoverageReport(rules: corpus)
        #expect(report.totalRuleCount == corpus.count)
        // Three rules self-classify .partial pending catalog-level promotion review
        // (ADR 0001 Q3): the honest reentrancy stub, plus ObservedObjectOwnedByView
        // and GlobalSharedDependency, whose authors judged promotion to
        // .supported/.research to be the catalog validator's job, not the rule's own.
        #expect(report.supportStateCounts[.partial] == 3)
        #expect(report.supportStateCounts[.externalRuntimeRequired] == 1)
        #expect(report.byDetectionMode[.deterministic]?.count == 4)
        #expect(report.byDetectionMode[.derived]?.count == 1)
        #expect(report.byDetectionMode[.heuristic]?.count == 1)
        #expect(report.byDetectionMode[.external]?.count == 1)
        #expect(report.byScope[.project]?.count == 1)
        #expect(report.byScope[.external]?.count == 1)
    }

    @Test("SM-4: no rule in this syntax-only corpus declares an unrelated heavy capability")
    func syntaxOnlyRulesStaySelective() {
        let engine = CapabilityResolutionEngine()
        let syntaxOnly = corpus.filter { $0.requirements.capabilities == [.syntax] }
        let resolution = engine.resolve(enabledRules: syntaxOnly)
        #expect(resolution.capabilities == [.syntax])
        #expect(!resolution.isNeeded(.gitHistory))
        #expect(!resolution.isNeeded(.runtimeEvidence))
        #expect(!resolution.isNeeded(.externalEvidence))
    }
}
