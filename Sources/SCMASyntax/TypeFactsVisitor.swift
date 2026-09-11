import SCMACore
import SwiftSyntax

final class TypeFactsVisitor: SyntaxVisitor {
    let root: SyntaxIdentifier
    let owner: TypeKey
    var properties: Set<String> = []
    var references: Set<String> = []

    init(root: SyntaxIdentifier, owner: TypeKey) {
        self.root = root
        self.owner = owner
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if directOwner(of: Syntax(node), module: owner.module) == owner {
            for binding in node.bindings { properties.formUnion(bindingNames(binding.pattern)) }
        }
        return .visitChildren
    }
    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        if node.parent?.is(MemberTypeSyntax.self) != true { references.insert(cleanName(node.name.text)) }
        return .visitChildren
    }
    override func visit(_ node: MemberTypeSyntax) -> SyntaxVisitorContinueKind {
        if node.parent?.is(MemberTypeSyntax.self) != true, let name = typeName(TypeSyntax(node)) {
            references.insert(name)
        }
        return .visitChildren
    }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let name = expressionName(node.calledExpression) { references.insert(name) }
        return .visitChildren
    }
    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let base = node.base, let name = expressionName(base) { references.insert(name) }
        return .visitChildren
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        node.id == root ? .visitChildren : .skipChildren
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        node.id == root ? .visitChildren : .skipChildren
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        node.id == root ? .visitChildren : .skipChildren
    }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        node.id == root ? .visitChildren : .skipChildren
    }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        node.id == root ? .visitChildren : .skipChildren
    }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        // A nested protocol's requirements are not the enclosing type's properties or references.
        .skipChildren
    }
    override func visit(_ node: IfConfigClauseSyntax) -> SyntaxVisitorContinueKind {
        // `os(iOS)` in a `#if` condition is not a type reference.
        if let elements = node.elements { walk(elements) }
        return .skipChildren
    }
}
