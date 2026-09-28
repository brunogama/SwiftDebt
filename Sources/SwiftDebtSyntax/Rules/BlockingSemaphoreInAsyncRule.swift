import Foundation
import SwiftDebtCore
import SwiftParser
import SwiftSyntax

/// Analysis context for `BlockingSemaphoreInAsyncRule`: a single source
/// unit's raw text. Parsing happens inside the rule so the rule stays a
/// self-contained syntax-scope implementation (PRD FR-14) without depending
/// on a shared parse-tree cache that doesn't exist yet.
public struct BlockingSemaphoreRuleContext: AnalysisContextProtocol {
    public let path: String
    public let sourceText: String

    public init(path: String, sourceText: String) {
        self.path = path
        self.sourceText = sourceText
    }
}

/// One `DispatchSemaphore.wait()` call site found in a source unit, together
/// with the lexical facts observed for it. Never a `FindingID` - this is an
/// evidence-collection intermediate, not a reported identity (Invariant Q4).
public struct BlockingSemaphoreDetection: Hashable, Sendable {
    public let path: String
    public let line: Int?
    public let column: Int?
    public let isAsyncContext: Bool
    public let isMainActorContext: Bool

    public init(
        path: String, line: Int?, column: Int?, isAsyncContext: Bool, isMainActorContext: Bool
    ) {
        self.path = path
        self.line = line
        self.column = column
        self.isAsyncContext = isAsyncContext
        self.isMainActorContext = isMainActorContext
    }
}

/// Concrete sink `BlockingSemaphoreInAsyncRule` emits Detections through.
/// `RuleImplementation.detect` only receives the `DetectionEmitter` marker
/// protocol (Detection construction and sink wiring are explicitly out of
/// this pilot's scope - see `RuleDefinition.swift`), so this rule defines its
/// own minimal concrete emitter and downcasts to it, rather than inventing a
/// shared sink type that would speculatively commit the wider catalog.
public final class BlockingSemaphoreDetectionEmitter: DetectionEmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BlockingSemaphoreDetection] = []

    public var detections: [BlockingSemaphoreDetection] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public init() {}

    public func record(_ detection: BlockingSemaphoreDetection) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(detection)
    }
}

/// research #12 / addendum J: `DispatchSemaphore.wait()` called from a
/// context that is already async or `@MainActor`-isolated blocks a thread
/// the concurrency runtime expects to keep making progress. This is a local
/// lexical-scope check only: it walks up the enclosing function/type syntax
/// to see whether that syntax is `async` or carries `@MainActor`, not a full
/// isolation analyzer.
public struct BlockingSemaphoreInAsyncRule: RuleImplementation {
    public typealias Context = BlockingSemaphoreRuleContext

    public let definition: RuleDefinition
    public let implementationRevision: ImplementationRevision = 1

    public init() {
        self.definition = RuleDefinition(
            identity: RuleIdentity("concurrency.blocking-semaphore-in-async"),
            metadata: RuleMetadata(
                title: "DispatchSemaphore.wait() blocks an async or @MainActor context",
                category: .concurrency,
                provenance: [RuleProvenance(researchItem: 12, note: "addendum J")],
                supportState: .supported
            ),
            scope: .syntax,
            mode: .deterministic,
            requirements: RuleRequirements([.syntax]),
            evidenceContract: EvidenceContract(
                required: .all([
                    .fact(EvidenceRequirement(key: "semaphoreWaitCall", kind: .syntax)),
                    .any([
                        .fact(EvidenceRequirement(key: "asyncContext", kind: .syntax)),
                        .fact(EvidenceRequirement(key: "mainActorContext", kind: .syntax)),
                    ]),
                ])
            ),
            semanticRevision: 1
        )
    }

    public func detect(in context: Context, emit: DetectionEmitter) throws {
        let sink = emit as? BlockingSemaphoreDetectionEmitter
        let tree = Parser.parse(source: context.sourceText)
        let converter = SourceLocationConverter(fileName: context.path, tree: tree)
        let collector = SemaphoreWaitCallCollector()
        collector.walk(tree)

        for call in collector.calls {
            var facts: Set<String> = ["semaphoreWaitCall"]
            if call.isAsyncContext { facts.insert("asyncContext") }
            if call.isMainActorContext { facts.insert("mainActorContext") }

            guard EvidencePredicateEvaluator.evaluate(
                definition.evidenceContract.required, availableFacts: facts
            ) else { continue }

            let location = converter.location(for: call.position)
            sink?.record(
                BlockingSemaphoreDetection(
                    path: context.path,
                    line: location.line,
                    column: location.column,
                    isAsyncContext: call.isAsyncContext,
                    isMainActorContext: call.isMainActorContext
                )
            )
        }
    }
}
