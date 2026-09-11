import SCMACore
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

package struct SwiftSyntaxParser: SourceParsing {
    package init() {}

    package func parse(_ source: SourceUnit) -> ParsedSource {
        let tree = Parser.parse(source: source.content)
        let converter = SourceLocationConverter(fileName: source.path, tree: tree)
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
            let location = converter.location(for: diagnostic.position)
            return AnalysisDiagnostic(
                severity: diagnostic.diagMessage.severity == .error ? .error : .warning,
                message: diagnostic.message,
                location: SCMACore.SourceLocation(file: source.path, line: location.line, column: location.column)
            )
        }
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            // Error recovery is useful to editors, but must not manufacture quality metrics.
            return ParsedSource(
                path: source.path, module: source.module, types: [], functions: [],
                lines: [], topLevelVariables: 0, diagnostics: diagnostics)
        }
        let imports = ImportVisitor()
        imports.walk(tree)
        let collector = DeclarationCollector(source: source, converter: converter, imports: imports.modules)
        collector.walk(tree)
        return ParsedSource(
            path: source.path, module: source.module, types: collector.types,
            functions: collector.functions, lines: collector.sourceLines.codeLines(tree),
            topLevelVariables: collector.topLevelVariables, diagnostics: diagnostics
        )
    }
}

private final class ImportVisitor: SyntaxVisitor {
    var modules: Set<String> = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if let component = node.path.first { modules.insert(cleanName(component.name.text)) }
        return .skipChildren
    }
}

private final class DeclarationCollector: SyntaxVisitor {
    let source: SourceUnit
    let sourceLines: SourceLines
    let imports: Set<String>
    var types: [TypeFragment] = []
    var functions: [FunctionFacts] = []
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
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let name = typeName(node.extendedType) { addType(Syntax(node), name: name, kind: "extension") }
        return .visitChildren
    }
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            addFunction(
                Syntax(node), name: cleanName(node.name.text), parameters: node.signature.parameterClause.parameters,
                body: body)
        }
        return .visitChildren
    }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body {
            addFunction(Syntax(node), name: "init", parameters: node.signature.parameterClause.parameters, body: body)
        }
        return .visitChildren
    }
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if let body = node.body { addFunction(Syntax(node), name: "deinit", parameters: [], body: body) }
        return .visitChildren
    }
    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        // Property and subscript accessors are callables for LOCF/CCF/NOPF/WMCC/NOAV, not for NOMC.
        let declared: (name: String, parameters: FunctionParameterListSyntax, decl: Syntax)?
        if let binding = node.parent?.as(PatternBindingSyntax.self), let variable = binding.parent?.parent,
            let name = bindingNames(binding.pattern).sorted().first
        {
            declared = (name, [], variable)
        } else if let subscriptDecl = node.parent?.as(SubscriptDeclSyntax.self) {
            declared = ("subscript", subscriptDecl.parameterClause.parameters, Syntax(subscriptDecl))
        } else {
            declared = nil
        }
        guard let declared else { return .visitChildren }
        switch node.accessors {
        case .getter(let statements):
            addFunction(
                Syntax(node), kind: .accessor, name: "\(declared.name).get", parameters: declared.parameters,
                statements: statements, ownerAnchor: declared.decl)
        case .accessors(let accessors):
            for accessor in accessors {
                guard let body = accessor.body else { continue }
                let kind = accessor.accessorSpecifier.text
                let implicit: Set<String> =
                    switch kind {
                    case "set", "willSet": [accessor.parameters.map { cleanName($0.name.text) } ?? "newValue"]
                    case "didSet": [accessor.parameters.map { cleanName($0.name.text) } ?? "oldValue"]
                    default: []
                    }
                addFunction(
                    Syntax(accessor), kind: .accessor, name: "\(declared.name).\(kind)",
                    parameters: declared.parameters, statements: body.statements, ownerAnchor: declared.decl,
                    implicitNames: implicit)
            }
        }
        return .visitChildren
    }
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        var parent = node.parent
        var global = true
        while let current = parent {
            if nominalName(current) != nil || current.is(ProtocolDeclSyntax.self)
                || current.is(CodeBlockSyntax.self) || isCallableBoundary(current)
            {
                global = false
                break
            }
            parent = current.parent
        }
        if global { topLevelVariables += node.bindings.reduce(0) { $0 + bindingNames($1.pattern).count } }
        return .visitChildren
    }

    private func addType(_ node: Syntax, name: String, kind: String) {
        let key = TypeKey(module: source.module, name: qualifiedName(of: node, ownName: name))
        let visitor = TypeFactsVisitor(root: node.id, owner: key)
        visitor.walk(node)
        types.append(
            TypeFragment(
                key: key, kind: kind, isExtension: kind == "extension", location: sourceLines.location(node),
                codeLines: sourceLines.codeLines(node).count, propertyNames: visitor.properties,
                referencedTypes: visitor.references, importedModules: imports
            ))
    }

    private func addFunction(
        _ node: Syntax, name: String, parameters: FunctionParameterListSyntax, body: CodeBlockSyntax
    ) {
        addFunction(
            node, kind: .method, name: name, parameters: parameters, statements: body.statements, ownerAnchor: node)
    }

    private func addFunction(
        _ node: Syntax, kind: CallableKind, name: String, parameters: FunctionParameterListSyntax,
        statements: CodeBlockItemListSyntax, ownerAnchor: Syntax, implicitNames: Set<String> = []
    ) {
        let owner = directOwner(of: ownerAnchor, module: source.module)
        let names = Set(
            parameters.compactMap { parameter -> String? in
                let value = cleanName((parameter.secondName ?? parameter.firstName).text)
                return value == "_" ? nil : value
            }
        ).union(implicitNames)
        let visitor = BodyVisitor(parameters: names)
        visitor.walk(statements)
        let labels = parameters.map { cleanName($0.firstName.text) + ":" }.joined()
        let prefix = owner?.displayName ?? source.module
        functions.append(
            FunctionFacts(
                name: "\(prefix).\(name)(\(labels))", kind: kind, owner: owner, location: sourceLines.location(node),
                codeLines: sourceLines.codeLines(statements).count, complexity: visitor.complexity,
                parameters: parameters.count, bareReferences: visitor.bareReferences,
                explicitSelfReferences: visitor.explicitSelfReferences, shadowedNames: visitor.shadowedNames
            ))
    }
}
