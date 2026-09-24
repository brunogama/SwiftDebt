import SwiftDebtCore
import SwiftSyntax

public struct NonisolatedUnsafeActorMemberRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.concurrency"),
        id: RuleID(validated: "actor-nonisolated-unsafe")
    )
    public static let metadata = RuleMetadata(
        name: "Nonisolated unsafe actor member",
        defaultSeverity: .information,
        remediation: "Review and document the synchronization that makes this actor-isolation opt-out safe."
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports nonisolated(unsafe) modifiers on direct actor member declarations, including direct members in every #if branch. Actor extensions are outside this syntax-only contract.",
        rationale:
            "nonisolated(unsafe) opts the declaration out of static isolation checking. This observation does not evaluate conditional compilation, bind extensions, or prove a race."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        NonisolatedUnsafeActorMemberVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class NonisolatedUnsafeActorMemberVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: DeclModifierSyntax) -> SyntaxVisitorContinueKind {
        guard
            node.name.tokenKind == .keyword(.nonisolated),
            let detail = node.detail?.detail,
            detail.text == "unsafe",
            isDirectActorMember(node)
        else { return .visitChildren }

        emit(
            at: detail,
            message:
                "This nonisolated(unsafe) actor member opts out of static isolation checking; review its synchronization assumptions."
        )
        return .visitChildren
    }

    private func isDirectActorMember(_ modifier: DeclModifierSyntax) -> Bool {
        var declarationCount = 0
        var ancestor = modifier.parent
        while let current = ancestor {
            if current.is(ActorDeclSyntax.self) {
                return declarationCount == 1
            }
            if current.as(DeclSyntax.self) != nil, !current.is(IfConfigDeclSyntax.self) {
                declarationCount += 1
                if declarationCount > 1 { return false }
            }
            ancestor = current.parent
        }
        return false
    }
}
