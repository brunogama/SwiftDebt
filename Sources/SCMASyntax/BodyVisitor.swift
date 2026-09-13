import SwiftSyntax

/// Policy is deliberately explicit; the paper does not define Swift decision-node rules.
/// No state is shared between parses or tasks.
///
/// Shadowing is lexically scoped: a local binding hides a same-named field reference only
/// inside the construct that introduces it (a code block, an `if`/`while`/`for`/`switch case`/
/// `catch` clause, or the remainder of the enclosing block for `guard`).
final class BodyVisitor: SyntaxVisitor {
    var complexity = 1
    var cognitiveComplexity = 0
    var maxNestingDepth = 0
    /// Bare identifiers that were not shadowed at their point of use.
    var bareReferences: Set<String> = []
    var explicitSelfReferences: Set<String> = []
    /// Every local binding name seen anywhere in the body; informational.
    var shadowedNames: Set<String>
    private var scopes: [Set<String>]
    private var nestingDepth = 0

    init(parameters: Set<String>) {
        shadowedNames = parameters
        scopes = [parameters]
        super.init(viewMode: .sourceAccurate)
    }

    private func isShadowed(_ name: String) -> Bool {
        scopes.contains { $0.contains(name) }
    }
    private func declare(_ name: String) {
        shadowedNames.insert(name)
        scopes[scopes.count - 1].insert(name)
    }
    private func push() -> SyntaxVisitorContinueKind {
        scopes.append([])
        return .visitChildren
    }
    private func pop() { scopes.removeLast() }
    private func recordFlowBreak() {
        cognitiveComplexity += 1 + nestingDepth
    }
    private func enterNestedFlow() -> SyntaxVisitorContinueKind {
        nestingDepth += 1
        maxNestingDepth = max(maxNestingDepth, nestingDepth)
        return push()
    }
    private func leaveNestedFlow() {
        pop()
        nestingDepth -= 1
    }

    // Scope-introducing constructs. Decision counting happens in the same overrides.
    override func visit(_ node: CodeBlockSyntax) -> SyntaxVisitorContinueKind { push() }
    override func visitPost(_ node: CodeBlockSyntax) { pop() }
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        recordFlowBreak()
        return enterNestedFlow()
    }
    override func visitPost(_ node: IfExprSyntax) { leaveNestedFlow() }
    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        // Guard bindings live in the enclosing scope; no push.
        complexity += 1
        recordFlowBreak()
        return .visitChildren
    }
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        recordFlowBreak()
        return enterNestedFlow()
    }
    override func visitPost(_ node: ForStmtSyntax) { leaveNestedFlow() }
    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        recordFlowBreak()
        return enterNestedFlow()
    }
    override func visitPost(_ node: WhileStmtSyntax) { leaveNestedFlow() }
    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        recordFlowBreak()
        nestingDepth += 1
        maxNestingDepth = max(maxNestingDepth, nestingDepth)
        return .visitChildren
    }
    override func visitPost(_ node: RepeatStmtSyntax) { nestingDepth -= 1 }
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        recordFlowBreak()
        nestingDepth += 1
        maxNestingDepth = max(maxNestingDepth, nestingDepth)
        scopes.append(node.catchItems.isEmpty ? ["error"] : [])
        return .visitChildren
    }
    override func visitPost(_ node: CatchClauseSyntax) {
        pop()
        nestingDepth -= 1
    }
    override func visit(_ node: SwitchCaseSyntax) -> SyntaxVisitorContinueKind {
        if node.label.is(SwitchCaseLabelSyntax.self) {
            complexity += 1
            recordFlowBreak()
        }
        return enterNestedFlow()
    }
    override func visitPost(_ node: SwitchCaseSyntax) { leaveNestedFlow() }
    override func visit(_ node: UnresolvedTernaryExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        recordFlowBreak()
        return .visitChildren
    }
    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        complexity += 1
        recordFlowBreak()
        return .visitChildren
    }
    // A binding's initializer is evaluated before the name exists: `if let title = Optional(title)`
    // reads the field `title`, then shadows it.
    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        if let initializer = node.initializer { walk(initializer) }
        walk(node.pattern)
        return .skipChildren
    }
    override func visit(_ node: MatchingPatternConditionSyntax) -> SyntaxVisitorContinueKind {
        walk(node.initializer)
        walk(node.pattern)
        return .skipChildren
    }
    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let initializer = node.initializer { walk(initializer) }
        walk(node.pattern)
        if let accessorBlock = node.accessorBlock { walk(accessorBlock) }
        return .skipChildren
    }
    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        // `#if A && B` is a compile-time condition, not a runtime decision.
        if let elements = node.elements { walk(elements) }
        return .skipChildren
    }
    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        // Unfolded parser expressions still expose short-circuit operators as tokens.
        if case .binaryOperator(let text) = token.tokenKind, text == "&&" || text == "||" {
            complexity += 1
            recordFlowBreak()
        }
        return .visitChildren
    }
    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = cleanName(node.baseName.text)
        if let member = node.parent?.as(MemberAccessExprSyntax.self), member.declName.id == node.id {
            if let base = member.base, let receiver = expressionName(base), receiver == "self" || receiver == "Self" {
                explicitSelfReferences.insert(name)
            }
            return .skipChildren
        }
        if !isShadowed(name) { bareReferences.insert(name) }
        return .skipChildren
    }
    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        let name = cleanName(node.identifier.text)
        if name != "_" { declare(name) }
        return .skipChildren
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        declare(cleanName(node.name.text))
        return .skipChildren
    }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
}
