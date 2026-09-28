import Foundation
import Testing

@testable import SwiftDebtCore

/// TASK-004: verifies the `concurrency.actor-reentrancy` acceptance-corpus
/// stub (research #19) is an honest `.partial` claim that the real catalog
/// validator accepts, and that the stub implementation never fabricates a
/// pass or a Detection - even when handed source that looks like a textbook
/// reentrancy bug.
@Suite("Actor reentrancy partial stub (TASK-004)")
struct ActorReentrancyPartialStubTests {

    /// A textbook actor-reentrancy shape: an invariant established before an
    /// `await`, then used again afterward without revalidation. If any real
    /// sensor existed, this is exactly the input it should flag.
    private static let textbookReentrancyFixture = """
        actor Counter {
            private var balance = 0
            private var isProcessing = false

            func withdraw(_ amount: Int) async {
                guard !isProcessing else { return }
                isProcessing = true
                await externalNotifier.notify(amount)
                // Reentrant call could have run here while suspended above.
                if balance >= amount {
                    balance -= amount
                }
                isProcessing = false
            }
        }
        """

    // MARK: - Definition shape

    @Test func definitionDeclaresTheFourIntraproceduralRequirements() {
        let definition = ActorReentrancyRule.definition
        #expect(definition.identity == RuleIdentity("concurrency.actor-reentrancy"))
        #expect(definition.metadata.supportState == .partial)
        #expect(
            definition.requirements.capabilities
                == [.syntax, .isolation, .controlFlow, .dataFlow]
        )
        #expect(definition.metadata.provenance.map(\.researchItem) == [19])
    }

    @Test func evidenceContractIsAllOfTheFourNamedFacts() throws {
        guard case .all(let children) = ActorReentrancyRule.evidenceContract.required else {
            Issue.record("expected the required predicate to be an 'all'")
            return
        }
        #expect(children.count == 4)
        let facts = try children.map { child throws -> EvidenceRequirement in
            guard case .fact(let requirement) = child else {
                Issue.record("expected every child to be a plain fact, got \(child)")
                throw TestError.unexpectedShape
            }
            return requirement
        }
        #expect(facts.map(\.key) == [
            "invariantEstablished", "suspensionPoint", "postSuspensionUse",
            "noSufficientRevalidation",
        ])
    }

    private enum TestError: Error { case unexpectedShape }

    // MARK: - Stub behavior: never .complete, never a Detection

    @Test func stubNeverReportsComplete() {
        let stub = ActorReentrancyPartialStub()
        let context = ActorReentrancySourceUnitContext(sourceText: Self.textbookReentrancyFixture)

        let observation = stub.observe(in: context)

        #expect(observation != .complete)
        #expect(observation == .unavailable(reason: .capabilityNotProvided(.controlFlow)))
        #expect(observation.provesAbsenceWhenNoDetection == false)
    }

    @Test func stubNeverEmitsADetectionAgainstATextbookReentrancyFixture() throws {
        let stub = ActorReentrancyPartialStub()
        let context = ActorReentrancySourceUnitContext(sourceText: Self.textbookReentrancyFixture)
        let emitter = NoOpDetectionEmitter()

        // `DetectionEmitter` (`RuleDefinition.swift`) is currently a
        // Sendable marker protocol with no emission API - Detection
        // construction and R1 reconciliation wiring are a downstream unit's
        // responsibility. There is therefore no method on `emit` this call
        // could invoke to produce a Detection; completing without throwing
        // is the strongest available proof that nothing was emitted.
        try stub.detect(in: context, emit: emitter)
    }

    @Test func stubNeverReportsCompleteAgainstAnEmptySourceEither() {
        // Absence of a textbook bug in the input must not change the
        // honest answer: the stub has no sensor either way.
        let stub = ActorReentrancyPartialStub()
        let context = ActorReentrancySourceUnitContext(sourceText: "")

        #expect(stub.observe(in: context) != .complete)
    }

    // MARK: - Catalog validator accepts this exact combination (ADR 0001 Q3)

    @Test func realValidatorAcceptsPartialSupportStateWithAnUnsatisfiedContract() throws {
        let yaml = try fixtureContents("task004-actor-reentrancy-partial-stub.yaml")

        let definitions = try RuleManifestParser.parse(yaml: yaml)

        #expect(definitions.count == 1)
        let parsed = try #require(definitions.first)

        // Compare everything the validator computes except the free-text
        // provenance note (YAML folded-scalar whitespace collapsing is not
        // what this test is proving).
        #expect(parsed.identity == ActorReentrancyRule.definition.identity)
        #expect(parsed.metadata.title == ActorReentrancyRule.definition.metadata.title)
        #expect(parsed.metadata.category == ActorReentrancyRule.definition.metadata.category)
        #expect(parsed.metadata.supportState == ActorReentrancyRule.definition.metadata.supportState)
        #expect(
            parsed.metadata.provenance.map(\.researchItem)
                == ActorReentrancyRule.definition.metadata.provenance.map(\.researchItem)
        )
        #expect(parsed.scope == ActorReentrancyRule.definition.scope)
        #expect(parsed.mode == ActorReentrancyRule.definition.mode)
        #expect(parsed.requirements == ActorReentrancyRule.definition.requirements)
        #expect(parsed.evidenceContract == ActorReentrancyRule.definition.evidenceContract)
        #expect(parsed.semanticRevision == ActorReentrancyRule.definition.semanticRevision)
    }

    @Test func collectErrorsAlsoReportsNoErrorsForThisEntry() throws {
        let yaml = try fixtureContents("task004-actor-reentrancy-partial-stub.yaml")

        let (definitions, errors) = RuleManifestParser.collectErrors(yaml: yaml)

        #expect(errors.isEmpty)
        #expect(definitions.count == 1)
    }

    // MARK: - Helpers

    /// Concrete stand-in so a test can pass something for `emit`.
    /// `DetectionEmitter` exposes no emission API yet, so this has nothing
    /// to implement.
    private struct NoOpDetectionEmitter: DetectionEmitter {}

    private func fixtureContents(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RuleCatalogManifest")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
