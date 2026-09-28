import Foundation
import Testing

@testable import SwiftDebtCore

/// Proves R1's rule execution path (`MetricsCalculator` -> `Metric` ->
/// `Finding`/`AnalysisReport`) and R2's cataloging types (`RuleDefinition`,
/// `RuleImplementation`, `ObservationState`) compile and run side by side in
/// the same target, per PRD section 8: "R2 depends on R1 Rule/Detection/
/// Reconciler/Finding/AnalysisSnapshot/Policy separation... New capabilities
/// must not change existing Rule Identity."
///
/// What this test demonstrates: an unmodified R1 analysis run
/// (`MetricsCalculator.analyze`) produces its ordinary `AnalysisReport`, and
/// a from-scratch R2 `RuleDefinition` plus a stub `RuleImplementation`
/// construct and execute independently, without either type referencing or
/// depending on the other.
///
/// What this test does NOT demonstrate: it is not an integration - no R1
/// Finding is reconciled through R2's `RuleDefinition`/`ObservationState`,
/// and no `RuleImplementation` observes real R1 output. That wiring is
/// future, separate work; this only proves non-interference between the two
/// type families today.
@Suite("R1/R2 coexistence")
struct R1R2CoexistenceTests {
    @Test("R1 MetricsCalculator runs unchanged alongside an R2 RuleDefinition")
    func r1AndR2CoexistWithoutInterference() throws {
        // --- R1 side: unmodified rule execution path. ---
        let parsed = ParsedSource(
            path: "Widget.swift", module: "Workspace", types: [], functions: [],
            lines: [CodeLine(number: 1, signature: "struct Widget {}")],
            topLevelVariables: 0, diagnostics: []
        )
        let report = try MetricsCalculator().analyze([parsed], options: AnalysisOptions())
        #expect(report.metrics.count == Metric.allCases.count)

        // --- R2 side: a from-scratch RuleDefinition + stub RuleImplementation. ---
        let definition = RuleDefinition(
            identity: RuleIdentity("coexistence.demo.rule"),
            metadata: RuleMetadata(
                title: "Coexistence demo rule",
                category: .style,
                provenance: [RuleProvenance(researchItem: 0, note: "coexistence proof only")],
                supportState: .research
            ),
            scope: .syntax,
            mode: .deterministic,
            requirements: RuleRequirements([.syntax]),
            evidenceContract: EvidenceContract(
                required: .fact(EvidenceRequirement(key: "demo", kind: .syntax))
            ),
            semanticRevision: 1
        )

        let implementation = StubRuleImplementation(definition: definition)
        #expect(implementation.definition.identity == definition.identity)

        let recorder = DetectionRecorder()
        try implementation.detect(in: StubContext(), emit: StubEmitter { recorder.record($0) })
        #expect(recorder.recorded == ["stub-detection"])

        // Neither side mutated or referenced the other.
        #expect(report.metrics.count == Metric.allCases.count)
        #expect(definition.identity.rawValue == "coexistence.demo.rule")
    }
}

/// Records what a `StubRuleImplementation` emits, so the test can assert
/// `detect` actually ran rather than merely compiling.
private final class DetectionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(value)
    }

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// Minimal `AnalysisContextProtocol` conformer - a real context type is
/// future work for the analysis-engine unit, out of scope here.
private struct StubContext: AnalysisContextProtocol {}

/// Minimal `DetectionEmitter` conformer that records what was emitted, so
/// the test can assert `detect` actually ran rather than merely compiling.
private struct StubEmitter: DetectionEmitter {
    let record: @Sendable (String) -> Void
}

/// Minimal `RuleImplementation` conformer used only to prove the protocol
/// is implementable alongside R1's unmodified execution path.
private struct StubRuleImplementation: RuleImplementation {
    typealias Context = StubContext

    let definition: RuleDefinition
    let implementationRevision: ImplementationRevision = 1

    func detect(in context: Context, emit: DetectionEmitter) throws {
        guard let emitter = emit as? StubEmitter else { return }
        emitter.record("stub-detection")
    }
}
