import SwiftDebtCore
import SwiftSyntax

// MARK: - Singleton binding + mutable stored property discovery

struct SingletonBinding {
    let owner: TypeKey
    let name: String
    let node: Syntax
    let mutablePropertyNames: Set<String>
}

/// Walks each nominal type declaration in the file exactly once, the same
/// way `TypeFactsVisitor` does (skipping into nested types), and for each
/// one collects both its own singleton-shaped static bindings and its own
/// mutable stored properties. Doing both in a single pass over each type's
/// own body avoids re-deriving "is this declaration directly owned by this
/// type" twice.
final class SingletonTypeVisitor: SyntaxVisitor {
    let module: String
    var bindings: [SingletonBinding] = []

    init(module: String) {
        self.module = module
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(Syntax(node), name: cleanName(node.name.text))
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(Syntax(node), name: cleanName(node.name.text))
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(Syntax(node), name: cleanName(node.name.text))
    }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        visitType(Syntax(node), name: cleanName(node.name.text))
    }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Extensions may add static singleton bindings too, but they never
        // add stored properties (Swift forbids stored properties in
        // extensions), so an extension can never satisfy the mutability
        // gate on its own. Treated as ordinary children to keep any type
        // decls nested lexically within it (rare) reachable.
        .visitChildren
    }

    private func visitType(_ node: Syntax, name: String) -> SyntaxVisitorContinueKind {
        let owner = selfOwner(node, name: name)
        let inner = TypeSingletonVisitor(root: node.id, owner: owner)
        inner.walk(node)
        for binding in inner.singletonBindings {
            bindings.append(
                SingletonBinding(
                    owner: owner, name: binding.name, node: binding.node,
                    mutablePropertyNames: inner.mutableProperties))
        }
        // Keep recursing so nested type declarations are still discovered;
        // `TypeSingletonVisitor` above already scoped this type's own
        // singleton bindings/mutable properties to just its own body.
        return .visitChildren
    }

    /// This type declaration's own key. `qualifiedName` already folds in
    /// any enclosing types (and marks local-in-function nesting), so a
    /// top-level type and a nested type both get a stable, distinct key.
    private func selfOwner(_ node: Syntax, name: String) -> TypeKey {
        TypeKey(module: module, name: qualifiedName(of: node, ownName: name))
    }
}

/// Scoped to a single type's own body (mirrors `TypeFactsVisitor`'s
/// nested-type skipping): collects that type's own singleton-shaped static
/// bindings and its own mutable stored properties in one pass.
final class TypeSingletonVisitor: SyntaxVisitor {
    let root: SyntaxIdentifier
    let owner: TypeKey
    var singletonBindings: [(name: String, node: Syntax)] = []
    var mutableProperties: Set<String> = []

    init(root: SyntaxIdentifier, owner: TypeKey) {
        self.root = root
        self.owner = owner
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard directOwner(of: Syntax(node), module: owner.module) == owner else {
            return .visitChildren
        }
        let isStaticLike = hasAnyModifier(Syntax(node), named: ["static", "class"])
        if isStaticLike {
            for binding in node.bindings {
                for name in bindingNames(binding.pattern)
                where GlobalSharedDependencyDetector.isSingletonBindingName(name) {
                    singletonBindings.append((name: name, node: Syntax(node)))
                }
            }
        } else if node.bindingSpecifier.text == "var" {
            for binding in node.bindings where isStored(binding) {
                mutableProperties.formUnion(bindingNames(binding.pattern))
            }
        }
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
        .skipChildren
    }

    /// A binding is a stored property when it has no accessor block, or its
    /// accessor block only observes (`willSet`/`didSet`) rather than
    /// computing (`get`/`set`), which still implies backing storage.
    /// `TypeFactsVisitor.properties` deliberately doesn't make this
    /// distinction (it only needs "is this name a property at all"), so it
    /// is captured here rather than by extending it.
    private func isStored(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else { return true }
        guard case .accessors(let accessors) = accessorBlock.accessors else { return false }
        return accessors.allSatisfy {
            let kind = $0.accessorSpecifier.text
            return kind == "willSet" || kind == "didSet"
        }
    }
}

// MARK: - Usage counting

/// Counts `TypeName.bindingName` member-access sites within the analyzed
/// source unit. Deliberately syntactic and source-unit-scoped: it does not
/// resolve unqualified references (e.g. a bare `shared` used from inside
/// the owning type itself) or cross-file usage, matching this rule's
/// `.sourceUnit` scope.
final class SingletonUsageVisitor: SyntaxVisitor {
    let typeName: String
    let bindingName: String
    var count = 0

    init(typeName: String, bindingName: String) {
        self.typeName = typeName
        self.bindingName = bindingName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if cleanName(node.declName.baseName.text) == bindingName,
            let base = node.base, expressionName(base) == typeName
        {
            count += 1
        }
        return .visitChildren
    }
}
