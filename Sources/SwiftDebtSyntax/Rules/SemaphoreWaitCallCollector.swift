import SwiftSyntax

/// One lexically-observed `DispatchSemaphore.wait()` call and the lexical
/// facts gathered by walking up its enclosing function/type syntax.
struct SemaphoreWaitCallSite {
    let position: AbsolutePosition
    let isAsyncContext: Bool
    let isMainActorContext: Bool
}

/// Walks a source unit's syntax tree tracking, per-scope, which local names
/// are known to be `DispatchSemaphore` values, then records every `.wait()`
/// call made on one of those names. For each call site it walks the node's
/// syntax ancestors to answer two purely lexical questions: is the nearest
/// enclosing function/closure `async`, and is that function or any enclosing
/// type declaration annotated `@MainActor`. No isolation inference, no
/// cross-file resolution - a name is "a semaphore" only when this file
/// declares it as one in the same lexical scope as the call.
final class SemaphoreWaitCallCollector: SyntaxVisitor {
    private(set) var calls: [SemaphoreWaitCallSite] = []
    private var semaphoreNames: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let name = node.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            declaresDispatchSemaphore(node) {
            semaphoreNames.insert(name)
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard
            let member = node.calledExpression.as(MemberAccessExprSyntax.self),
            member.declName.baseName.text == "wait",
            let base = member.base,
            isKnownSemaphoreReference(base)
        else {
            return .visitChildren
        }

        calls.append(
            SemaphoreWaitCallSite(
                position: node.positionAfterSkippingLeadingTrivia,
                isAsyncContext: isInAsyncContext(Syntax(node)),
                isMainActorContext: isInMainActorContext(Syntax(node))
            )
        )
        return .visitChildren
    }

    // MARK: - Semaphore-typed name tracking

    private func declaresDispatchSemaphore(_ node: PatternBindingSyntax) -> Bool {
        if let annotation = node.typeAnnotation?.type.as(IdentifierTypeSyntax.self),
            annotation.name.text == "DispatchSemaphore" {
            return true
        }
        if let call = node.initializer?.value.as(FunctionCallExprSyntax.self),
            let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
            callee.baseName.text == "DispatchSemaphore" {
            return true
        }
        return false
    }

    private func isKnownSemaphoreReference(_ expression: some ExprSyntaxProtocol) -> Bool {
        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            return semaphoreNames.contains(reference.baseName.text)
        }
        if let call = expression.as(FunctionCallExprSyntax.self),
            let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return callee.baseName.text == "DispatchSemaphore"
        }
        return false
    }

    // MARK: - Lexical scope walk-up

    /// The nearest enclosing function-like syntax node (function, closure,
    /// or accessor) is the only thing whose `async`-ness matters: `async`
    /// does not propagate from an outer function into a nested synchronous
    /// closure or vice versa.
    private func isInAsyncContext(_ node: Syntax) -> Bool {
        var current: Syntax? = Syntax(node)
        while let ancestor = current {
            if let function = ancestor.as(FunctionDeclSyntax.self) {
                return function.signature.effectSpecifiers?.asyncSpecifier != nil
            }
            if let closure = ancestor.as(ClosureExprSyntax.self) {
                return closure.signature?.effectSpecifiers?.asyncSpecifier != nil
            }
            if let accessor = ancestor.as(AccessorDeclSyntax.self) {
                return accessor.effectSpecifiers?.asyncSpecifier != nil
            }
            current = ancestor.parent
        }
        return false
    }

    /// Unlike `async`, `@MainActor` isolation is inherited from an enclosing
    /// type: a method on a `@MainActor` class is main-actor-isolated even
    /// when the method itself carries no attribute. So this walk keeps going
    /// past the nearest function up through every enclosing declaration.
    private func isInMainActorContext(_ node: Syntax) -> Bool {
        var current: Syntax? = Syntax(node)
        while let ancestor = current {
            if let attributes = declarationAttributes(ancestor), hasMainActorAttribute(attributes) {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    private func declarationAttributes(_ node: Syntax) -> AttributeListSyntax? {
        if let function = node.as(FunctionDeclSyntax.self) { return function.attributes }
        if let classDecl = node.as(ClassDeclSyntax.self) { return classDecl.attributes }
        if let structDecl = node.as(StructDeclSyntax.self) { return structDecl.attributes }
        if let actorDecl = node.as(ActorDeclSyntax.self) { return actorDecl.attributes }
        if let extensionDecl = node.as(ExtensionDeclSyntax.self) { return extensionDecl.attributes }
        if let enumDecl = node.as(EnumDeclSyntax.self) { return enumDecl.attributes }
        return nil
    }

    private func hasMainActorAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            guard let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self) else {
                return false
            }
            return identifier.name.text == "MainActor"
        }
    }
}
