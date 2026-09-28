import Foundation
import SwiftDebtCore
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

final class ImportVisitor: SyntaxVisitor {
    var modules: Set<String> = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if let component = node.path.first { modules.insert(cleanName(component.name.text)) }
        return .skipChildren
    }
}

private struct DeclaredAccessor {
    let name: String
    let parameters: FunctionParameterListSyntax
    let declaration: Syntax
}

struct FunctionDeclarationInput {
    let node: Syntax
    let kind: CallableKind
    let name: String
    let parameters: FunctionParameterListSyntax
    let statements: CodeBlockItemListSyntax
    let ownerAnchor: Syntax
    let implicitNames: Set<String>
}

final class DeclarationCollector: SyntaxVisitor {
    let source: SourceUnit
    let sourceLines: SourceLines
    let imports: Set<String>
    var types: [TypeFragment] = []
    var functions: [FunctionFacts] = []
    var closures: [ClosureFacts] = []
    var riskFacts: [SwiftRiskFact] = []
    var topLevelVariables = 0

    init(source: SourceUnit, converter: SourceLocationConverter, imports: Set<String>) {
        self.source = source
        self.sourceLines = SourceLines(file: source.path, converter: converter)
        self.imports = imports
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        addType(Syntax(node), name: cleanName(node.name.text), kind: "class")
        return .visitChildren
    }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addType(Syntax(node), name: cleanName(node.name.text), kind: "struct")
        return .visitChildren
    }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        addType(Syntax(node), name: cleanName(node.name.text), kind: "enum")
        return .visitChildren
    }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        addType(Syntax(node), name: cleanName(node.name.text), kind: "actor")
        return .visitChildren
    }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        addType(Syntax(node), name: cleanName(node.name.text), kind: "protocol")
        return .visitChildren
    }
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let name = typeName(node.extendedType) {
            addType(Syntax(node), name: name, kind: "extension")
        }
        return .visitChildren
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            addFunction(
                Syntax(node), name: cleanName(node.name.text),
                parameters: node.signature.parameterClause.parameters,
                body: body)
        }
        return .visitChildren
    }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            addFunction(
                Syntax(node), name: "init", parameters: node.signature.parameterClause.parameters,
                body: body)
        }
        return .visitChildren
    }
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            addFunction(Syntax(node), name: "deinit", parameters: [], body: body)
        }
        return .visitChildren
    }
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        // Property and subscript accessors are callables for LOCF/CCF/NOPF/WMCC/NOAV, not for NOMC.
        guard let declared = declaredAccessor(for: node) else { return .visitChildren }
        addAccessors(node, declared: declared)
        return .visitChildren
    }

    private func declaredAccessor(for node: AccessorBlockSyntax) -> DeclaredAccessor? {
        if let binding = node.parent?.as(PatternBindingSyntax.self),
            let variable = binding.parent?.parent,
            let name = bindingNames(binding.pattern).min()
        {
            return DeclaredAccessor(name: name, parameters: [], declaration: variable)
        }
        if let subscriptDecl = node.parent?.as(SubscriptDeclSyntax.self) {
            return DeclaredAccessor(
                name: "subscript",
                parameters: subscriptDecl.parameterClause.parameters,
                declaration: Syntax(subscriptDecl))
        }
        return nil
    }

    private func addAccessors(_ node: AccessorBlockSyntax, declared: DeclaredAccessor) {
        switch node.accessors {
        case .getter(let statements):
            addFunction(
                FunctionDeclarationInput(
                    node: Syntax(node), kind: .accessor, name: "\(declared.name).get",
                    parameters: declared.parameters, statements: statements,
                    ownerAnchor: declared.declaration, implicitNames: []))
        case .accessors(let accessors):
            for accessor in accessors {
                guard let body = accessor.body else { continue }
                let kind = accessor.accessorSpecifier.text
                let implicit: Set<String> =
                    switch kind {
                    case "set", "willSet":
                        [accessor.parameters.map { cleanName($0.name.text) } ?? "newValue"]
                    case "didSet":
                        [accessor.parameters.map { cleanName($0.name.text) } ?? "oldValue"]
                    default: []
                    }
                addFunction(
                    FunctionDeclarationInput(
                        node: Syntax(accessor), kind: .accessor,
                        name: "\(declared.name).\(kind)", parameters: declared.parameters,
                        statements: body.statements, ownerAnchor: declared.declaration,
                        implicitNames: implicit))
            }
        }
    }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        addClosure(node)
        return .visitChildren
    }
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if isGlobal(node) {
            recordGlobalVariable(node)
        } else if node.bindingSpecifier.text == "var",
            hasAnyModifier(Syntax(node), named: ["class", "static"])
        {
            riskFacts.append(
                SwiftRiskFact(
                    category: .mutableSharedState,
                    detail: "static var declaration",
                    location: sourceLines.location(node)
                )
            )
        }
        return .visitChildren
    }

    private func isGlobal(_ node: VariableDeclSyntax) -> Bool {
        var parent = node.parent
        while let current = parent {
            if nominalName(current) != nil || current.is(ProtocolDeclSyntax.self)
                || current.is(CodeBlockSyntax.self) || isCallableBoundary(current)
            {
                return false
            }
            parent = current.parent
        }
        return true
    }

    private func recordGlobalVariable(_ node: VariableDeclSyntax) {
        topLevelVariables += node.bindings.reduce(0) { $0 + bindingNames($1.pattern).count }
        if node.bindingSpecifier.text == "var" {
            riskFacts.append(
                SwiftRiskFact(
                    category: .mutableSharedState,
                    detail: "top-level var declaration",
                    location: sourceLines.location(node)
                )
            )
        }
    }

}
