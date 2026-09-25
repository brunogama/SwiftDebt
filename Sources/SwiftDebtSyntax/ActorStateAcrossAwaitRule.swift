import SwiftDebtCore
import SwiftSyntax

public struct ActorStateAcrossAwaitRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.concurrency"),
        id: RuleID(validated: "actor-state-across-await")
    )
    public static let metadata = RuleMetadata(
        name: "Actor state across await",
        defaultSeverity: .information,
        remediation: "Review assumptions about mutable actor state across the suspension point."
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports an await in a direct actor method when sequential statements before and after it explicitly access the same directly declared mutable actor property through self. Nested closures, actor extensions, and control-flow branches are outside this syntax-only contract.",
        rationale:
            "Other work may run on an actor while its method is suspended. This review signal does not prove that interleaving occurs or breaks an invariant."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        ActorStateAcrossAwaitVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class ActorStateAcrossAwaitVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ actor: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        var mutableProperties: Set<String> = []
        for member in actor.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard variable.bindingSpecifier.tokenKind == .keyword(.var) else { continue }
            guard
                !variable.modifiers.contains(where: {
                    $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.nonisolated)
                })
            else { continue }
            for binding in variable.bindings where isWritable(binding) {
                if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                    mutableProperties.insert(name)
                }
            }
        }

        guard !mutableProperties.isEmpty else { return .visitChildren }

        for member in actor.memberBlock.members {
            guard
                let function = member.decl.as(FunctionDeclSyntax.self),
                let body = function.body,
                !function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) })
            else { continue }

            let evidence = body.statements.map { statement in
                let collector = ActorStatementEvidenceCollector(mutableProperties: mutableProperties)
                if statement.item.is(ExprSyntax.self)
                    || statement.item.is(VariableDeclSyntax.self)
                    || statement.item.is(ReturnStmtSyntax.self)
                {
                    collector.walk(statement)
                }
                return collector.evidence
            }

            for index in evidence.indices where !evidence[index].awaitExpressions.isEmpty {
                let before = evidence[..<index].reduce(into: Set<String>()) {
                    $0.formUnion($1.accessedProperties)
                }
                let after = evidence[(index + 1)...].reduce(into: Set<String>()) {
                    $0.formUnion($1.accessedProperties)
                }
                guard !before.isDisjoint(with: after) else { continue }

                for awaitExpression in evidence[index].awaitExpressions {
                    emit(
                        at: awaitExpression.awaitKeyword,
                        continuitySubject: awaitExpression,
                        message:
                            "This actor method accesses mutable state on both sides of await; review assumptions that interleaving could change."
                    )
                }
            }
        }

        return .visitChildren
    }

    private func isWritable(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else { return true }
        switch accessorBlock.accessors {
        case .getter:
            return false
        case .accessors(let accessors):
            return accessors.contains {
                ["set", "willSet", "didSet", "_modify"].contains($0.accessorSpecifier.text)
            }
        }
    }
}

private struct ActorStatementEvidence {
    var accessedProperties: Set<String> = []
    var awaitExpressions: [AwaitExprSyntax] = []
}

private final class ActorStatementEvidenceCollector: SyntaxVisitor {
    private let mutableProperties: Set<String>
    private(set) var evidence = ActorStatementEvidence()

    init(mutableProperties: Set<String>) {
        self.mutableProperties = mutableProperties
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let base = node.base?.as(DeclReferenceExprSyntax.self),
            base.baseName.tokenKind == .keyword(.self),
            mutableProperties.contains(node.declName.baseName.text)
        {
            evidence.accessedProperties.insert(node.declName.baseName.text)
        }
        return .visitChildren
    }

    override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        evidence.awaitExpressions.append(node)
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}
