import Testing

@testable import SwiftDebtCore
@testable import SwiftDebtSyntax

@Suite("concurrency.blocking-semaphore-in-async")
struct BlockingSemaphoreInAsyncRuleTests {
    private let rule = BlockingSemaphoreInAsyncRule()

    private func detections(for source: String) throws -> [BlockingSemaphoreDetection] {
        let emitter = BlockingSemaphoreDetectionEmitter()
        let context = BlockingSemaphoreRuleContext(path: "Input.swift", sourceText: source)
        try rule.detect(in: context, emit: emitter)
        return emitter.detections
    }

    @Test func firesInsideAsyncFunction() throws {
        let source = """
            import Dispatch

            func loadAsync() async {
                let semaphore = DispatchSemaphore(value: 0)
                semaphore.wait()
            }
            """

        let found = try detections(for: source)
        #expect(found.count == 1)
        #expect(found[0].isAsyncContext)
        #expect(!found[0].isMainActorContext)
    }

    @Test func doesNotFireInsideOrdinarySynchronousFunction() throws {
        let source = """
            import Dispatch

            func loadSync() {
                let semaphore = DispatchSemaphore(value: 0)
                semaphore.wait()
            }
            """

        let found = try detections(for: source)
        #expect(found.isEmpty)
    }

    @Test func firesInsideMainActorAnnotatedClassMethod() throws {
        let source = """
            import Dispatch

            @MainActor
            final class ViewModel {
                func load() {
                    let semaphore = DispatchSemaphore(value: 0)
                    semaphore.wait()
                }
            }
            """

        let found = try detections(for: source)
        #expect(found.count == 1)
        #expect(!found[0].isAsyncContext)
        #expect(found[0].isMainActorContext)
    }

    @Test func doesNotFireWhenWaitIsCalledOnUnrelatedType() throws {
        let source = """
            struct NotASemaphore {
                func wait() {}
            }

            func loadAsync() async {
                let semaphore = NotASemaphore()
                semaphore.wait()
            }
            """

        let found = try detections(for: source)
        #expect(found.isEmpty)
    }

    // MARK: - EvidencePredicate boolean-algebra evaluation

    @Test func evidencePredicateRequiresSemaphoreFactRegardlessOfContext() {
        let contract = BlockingSemaphoreInAsyncRule().definition.evidenceContract
        // async fact present but no semaphore-wait fact: `.all` must still fail.
        #expect(!EvidencePredicateEvaluator.evaluate(contract.required, availableFacts: ["asyncContext"]))
    }

    @Test func evidencePredicateSatisfiedByEitherAsyncOrMainActorFact() {
        let contract = BlockingSemaphoreInAsyncRule().definition.evidenceContract
        #expect(
            EvidencePredicateEvaluator.evaluate(
                contract.required, availableFacts: ["semaphoreWaitCall", "asyncContext"]))
        #expect(
            EvidencePredicateEvaluator.evaluate(
                contract.required, availableFacts: ["semaphoreWaitCall", "mainActorContext"]))
        #expect(
            !EvidencePredicateEvaluator.evaluate(
                contract.required, availableFacts: ["semaphoreWaitCall"]))
    }

    @Test func evaluatorWalksNotAndNestedAllAny() {
        let predicate = EvidencePredicate.all([
            .not(.fact(EvidenceRequirement(key: "excluded", kind: .syntax))),
            .any([
                .fact(EvidenceRequirement(key: "a", kind: .syntax)),
                .all([
                    .fact(EvidenceRequirement(key: "b", kind: .syntax)),
                    .fact(EvidenceRequirement(key: "c", kind: .syntax)),
                ]),
            ]),
        ])

        #expect(EvidencePredicateEvaluator.evaluate(predicate, availableFacts: ["a"]))
        #expect(EvidencePredicateEvaluator.evaluate(predicate, availableFacts: ["b", "c"]))
        #expect(!EvidencePredicateEvaluator.evaluate(predicate, availableFacts: ["b"]))
        #expect(!EvidencePredicateEvaluator.evaluate(predicate, availableFacts: ["a", "excluded"]))
    }
}
