import SwiftDebtCore
import SwiftParser
import SwiftSyntax

/// A single `try!` occurrence found while evaluating ``ForceTryRule``.
///
/// This is deliberately a rule-local Detection shape, not a shared catalog
/// `Detection` type: per ``RuleDefinition``, Detection construction and R1
/// reconciliation wiring are future, separate work (see
/// `AnalysisContextProtocol`/`DetectionEmitter` doc comments). ``ForceTryRule``
/// only needs to prove `errors.force-try` observes syntax evidence and
/// reaches ``ObservationState/complete`` with the right locations.
public struct ForceTryDetection: Codable, Hashable, Sendable {
    public let location: SwiftDebtCore.SourceLocation

    public init(location: SwiftDebtCore.SourceLocation) {
        self.location = location
    }
}

/// Result of evaluating ``ForceTryRule`` against one source file: either a
/// verified-absence/verified-presence ``ObservationState/complete`` result
/// with zero or more detections, or a degraded state (never both).
public struct ForceTryOutcome: Sendable {
    public let state: ObservationState
    public let detections: [ForceTryDetection]

    public init(state: ObservationState, detections: [ForceTryDetection] = []) {
        self.state = state
        self.detections = detections
    }
}

/// Scope-appropriate context for `errors.force-try`: the parsed syntax tree
/// of a single source file, plus the path used to report locations. Concrete
/// per ``AnalysisContextProtocol``'s note that real contexts are a
/// downstream, scope-specific responsibility - this one is the `.syntax`
/// scope's.
public struct SyntaxFileContext: AnalysisContextProtocol {
    public let path: String
    public let tree: SourceFileSyntax
    public let converter: SourceLocationConverter

    public init(path: String, source: String) {
        self.path = path
        self.tree = Parser.parse(source: source)
        self.converter = SourceLocationConverter(fileName: path, tree: tree)
    }
}

/// Collects every ``ForceTryDetection`` emitted while evaluating a rule
/// against a ``SyntaxFileContext``. Concrete per ``DetectionEmitter``'s note
/// that Detection construction is deferred to a downstream unit - this
/// in-memory collector is `errors.force-try`'s own, scoped to this pilot.
public final class ForceTryEmitter: DetectionEmitter, @unchecked Sendable {
    private var storage: [ForceTryDetection] = []

    public init() {}

    func emit(_ detection: ForceTryDetection) {
        storage.append(detection)
    }

    public var detections: [ForceTryDetection] { storage }
}

private final class ForceTryVisitor: SyntaxVisitor {
    private let sourceLines: SourceLines

    var detections: [ForceTryDetection] = []

    init(sourceLines: SourceLines) {
        self.sourceLines = sourceLines
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.tokenKind == .exclamationMark {
            detections.append(ForceTryDetection(location: sourceLines.location(node)))
        }
        return .visitChildren
    }
}

/// `errors.force-try` (research #28, addendum J): a `try!` expression
/// discards its underlying error entirely, converting any thrown error into
/// an unconditional runtime trap. Deterministic syntax rule - the `try!`
/// spelling is unambiguous at the syntax level, no semantic or type
/// information is required to observe it.
public struct ForceTryRule: RuleImplementation {
    public typealias Context = SyntaxFileContext

    public let definition: RuleDefinition
    public let implementationRevision: ImplementationRevision = 1

    public init() {
        self.definition = RuleDefinition(
            identity: RuleIdentity("errors.force-try"),
            metadata: RuleMetadata(
                title: "Force try (`try!`) discards errors",
                category: .errorHandling,
                provenance: [RuleProvenance(researchItem: 28, note: "addendum J")],
                supportState: .supported
            ),
            scope: .syntax,
            mode: .deterministic,
            requirements: RuleRequirements([.syntax]),
            evidenceContract: EvidenceContract(
                required: .fact(EvidenceRequirement(key: "forceTryExpression", kind: .syntax))
            ),
            semanticRevision: 1
        )
    }

    public func detect(in context: Context, emit: DetectionEmitter) throws {
        guard let emitter = emit as? ForceTryEmitter else { return }
        let sourceLines = SourceLines(file: context.path, converter: context.converter)
        let visitor = ForceTryVisitor(sourceLines: sourceLines)
        visitor.walk(context.tree)
        for detection in visitor.detections {
            emitter.emit(detection)
        }
    }

    /// Convenience entry point mirroring how a rule of this scope/mode is
    /// actually evaluated end-to-end today: parse, walk, and always report
    /// ``ObservationState/complete`` (deterministic syntax detection has no
    /// way to be partial or unavailable per PRD FR-10/Invariant Q3 - the
    /// required evidence, the syntax tree, is always available once parsing
    /// succeeds).
    public func evaluate(path: String, source: String) throws -> ForceTryOutcome {
        let context = SyntaxFileContext(path: path, source: source)
        let emitter = ForceTryEmitter()
        try detect(in: context, emit: emitter)
        return ForceTryOutcome(state: .complete, detections: emitter.detections)
    }
}
