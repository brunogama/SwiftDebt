import SwiftDebtCore
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

struct RepositorySyntaxExtractor {
    func extract(
        _ sources: [SourceUnit],
        maximumAnalysisUnitsPerRule: Int = .max
    ) -> RepositorySyntaxFacts {
        var result = RepositorySyntaxFacts()
        let (nextUnitCount, unitCountOverflowed) = maximumAnalysisUnitsPerRule.addingReportingOverflow(1)
        let materializationLimit = unitCountOverflowed ? Int.max : nextUnitCount
        for source in sources {
            let tree = Parser.parse(source: source.content)
            let converter = SourceLocationConverter(fileName: source.path, tree: tree)
            let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
                let location = converter.location(for: diagnostic.position)
                return AnalysisDiagnostic(
                    severity: diagnostic.diagMessage.severity == .error ? .error : .warning,
                    message: diagnostic.message,
                    location: SwiftDebtCore.SourceLocation(
                        file: source.path,
                        line: location.line,
                        column: location.column
                    )
                )
            }
            result.diagnostics += diagnostics
            guard !diagnostics.contains(where: { $0.severity == .error }) else { continue }

            let materializedSwitchCount =
                result.repeatedSwitchUnits.count + result.conditionalSwitchLocations.count
            let visitor = RepositoryFactVisitor(
                source: source,
                converter: converter,
                maximumDataClumpUnits: max(0, materializationLimit - result.dataClumpUnits.count),
                maximumRepeatedSwitchFacts: max(0, materializationLimit - materializedSwitchCount)
            )
            visitor.walk(tree)
            result.dataClumpUnits += visitor.dataClumpUnits
            result.repeatedSwitchUnits += visitor.repeatedSwitchUnits
            result.conditionalSwitchLocations += visitor.conditionalSwitchLocations
        }
        result.dataClumpUnits.sort(by: dataClumpUnitOrder)
        result.repeatedSwitchUnits.sort(by: repeatedSwitchUnitOrder)
        result.conditionalSwitchLocations.sort(by: sourceLocationOrder)
        result.diagnostics.sort(by: diagnosticOrder)
        return result
    }
}

private final class RepositoryFactVisitor: SyntaxVisitor {
    let source: SourceUnit
    let converter: SourceLocationConverter
    let maximumDataClumpUnits: Int
    let maximumRepeatedSwitchFacts: Int
    var dataClumpUnits: [DataClumpUnit] = []
    var repeatedSwitchUnits: [RepeatedSwitchUnit] = []
    var conditionalSwitchLocations: [SwiftDebtCore.SourceLocation] = []

    init(
        source: SourceUnit,
        converter: SourceLocationConverter,
        maximumDataClumpUnits: Int,
        maximumRepeatedSwitchFacts: Int
    ) {
        self.source = source
        self.converter = converter
        self.maximumDataClumpUnits = maximumDataClumpUnits
        self.maximumRepeatedSwitchFacts = maximumRepeatedSwitchFacts
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        addPropertyUnit(node.memberBlock, declaration: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        addPropertyUnit(node.memberBlock, declaration: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        addPropertyUnit(node.memberBlock, declaration: Syntax(node), name: node.name.text)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        addParameterUnit(
            node.signature.parameterClause.parameters,
            declaration: Syntax(node),
            name: normalizedIdentifier(node.name.text),
            kind: .functionParameters
        )
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        addParameterUnit(
            node.signature.parameterClause.parameters,
            declaration: Syntax(node),
            name: "init",
            kind: .initializerParameters
        )
        return .visitChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        addParameterUnit(
            node.parameterClause.parameters,
            declaration: Syntax(node),
            name: "subscript",
            kind: .subscriptParameters
        )
        return .visitChildren
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        guard repeatedSwitchUnits.count + conditionalSwitchLocations.count < maximumRepeatedSwitchFacts else {
            return .visitChildren
        }
        let location = sourceLocation(node)
        var labels: [NormalizedTokenSequence] = []
        for element in node.cases {
            switch element {
            case .switchCase(let switchCase):
                labels.append(normalizedTokens(switchCase.label))
            case .ifConfigDecl:
                conditionalSwitchLocations.append(location)
                return .visitChildren
            }
        }
        guard labels.count >= 2, let discriminator = simpleDiscriminator(node.subject) else {
            return .visitChildren
        }
        let scope = nominalScope(of: Syntax(node), module: source.module)
        repeatedSwitchUnits.append(
            RepeatedSwitchUnit(
                scope: scope,
                discriminator: discriminator,
                caseShape: labels,
                displayName: "switch \(discriminator.displayValue) in \(scope)",
                location: location
            )
        )
        return .visitChildren
    }

    private func addParameterUnit(
        _ parameters: FunctionParameterListSyntax,
        declaration: Syntax,
        name: String,
        kind: RepositoryAnalysisUnitKind
    ) {
        guard dataClumpUnits.count < maximumDataClumpUnits else { return }
        let elements = Set(parameters.compactMap(parameterElement))
        guard !elements.isEmpty else { return }
        let owner = nominalScope(of: declaration, module: source.module)
        dataClumpUnits.append(
            DataClumpUnit(
                kind: kind,
                displayName: "\(owner).\(name)",
                location: sourceLocation(declaration),
                elements: elements
            )
        )
    }

    private func addPropertyUnit(_ members: MemberBlockSyntax, declaration: Syntax, name: String) {
        guard dataClumpUnits.count < maximumDataClumpUnits else { return }
        guard !hasCallableAncestor(declaration) else { return }
        var elements = Set<DataClumpElement>()
        for member in members.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self), !isTypeProperty(variable) else { continue }
            for binding in variable.bindings {
                guard isStoredProperty(binding),
                    let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                    let type = binding.typeAnnotation?.type
                else { continue }
                let propertyName = normalizedIdentifier(identifier.identifier.text)
                guard propertyName != "_" else { continue }
                elements.insert(
                    DataClumpElement(name: propertyName, normalizedType: normalizedTokens(type))
                )
            }
        }
        guard !elements.isEmpty else { return }
        dataClumpUnits.append(
            DataClumpUnit(
                kind: .nominalProperties,
                displayName: nominalScope(of: declaration, module: source.module) + "." + normalizedIdentifier(name),
                location: sourceLocation(declaration),
                elements: elements
            )
        )
    }

    private func parameterElement(_ parameter: FunctionParameterSyntax) -> DataClumpElement? {
        let token = parameter.secondName ?? parameter.firstName
        let name = normalizedIdentifier(token.text)
        guard name != "_" else { return nil }
        var typeTokens = normalizedTokens(parameter.attributes).tokens
        typeTokens += normalizedTokens(parameter.modifiers).tokens
        typeTokens += normalizedTokens(parameter.type).tokens
        if let ellipsis = parameter.ellipsis?.text {
            typeTokens.append(ellipsis)
        }
        let type = NormalizedTokenSequence(tokens: typeTokens)
        return DataClumpElement(name: name, normalizedType: type)
    }

    private func sourceLocation(_ node: some SyntaxProtocol) -> SwiftDebtCore.SourceLocation {
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SwiftDebtCore.SourceLocation(file: source.path, line: location.line, column: location.column)
    }
}
