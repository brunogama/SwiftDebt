import Foundation
import SwiftDebtCore
import SwiftSyntax

extension DeclarationCollector {
    func addType(_ node: Syntax, name: String, kind: String) {
        if kind == "actor" {
            riskFacts.append(
                SwiftRiskFact(
                    category: .actorIsolation,
                    detail: "actor declaration \(name)",
                    location: sourceLines.location(node),
                    confidence: .measuredSyntax
                )
            )
        }
        riskFacts.append(contentsOf: declarationRiskFacts(for: node, name: name))
        let key = TypeKey(module: source.module, name: qualifiedName(of: node, ownName: name))
        let visitor = TypeFactsVisitor(root: node.id, owner: key)
        visitor.walk(node)
        types.append(
            TypeFragment(
                key: key, kind: kind, isExtension: kind == "extension",
                location: sourceLines.location(node),
                codeLines: sourceLines.codeLines(node).count, propertyNames: visitor.properties,
                referencedTypes: visitor.references, importedModules: imports
            ))
    }

    func addFunction(
        _ node: Syntax, name: String, parameters: FunctionParameterListSyntax, body: CodeBlockSyntax
    ) {
        addFunction(
            FunctionDeclarationInput(
                node: node, kind: .method, name: name, parameters: parameters,
                statements: body.statements, ownerAnchor: node, implicitNames: []))
    }

    func addClosure(_ node: ClosureExprSyntax) {
        let names = closureParameterNames(node.signature)
        let visitor = BodyVisitor(parameters: names)
        visitor.walk(node.statements)
        closures.append(
            ClosureFacts(
                owner: directOwner(of: Syntax(node), module: source.module),
                location: sourceLines.location(node),
                codeLines: sourceLines.codeLines(node.statements).count,
                complexity: visitor.complexity,
                cognitiveComplexity: visitor.cognitiveComplexity,
                maxNestingDepth: visitor.maxNestingDepth,
                parameters: names.count
            ))
    }

    func closureParameterNames(_ signature: ClosureSignatureSyntax?) -> Set<String> {
        guard let parameterClause = signature?.parameterClause else { return [] }
        switch parameterClause {
        case .simpleInput(let parameters):
            return Set(
                parameters.compactMap { parameter in
                    let value = cleanName(parameter.name.text)
                    return value == "_" ? nil : value
                })
        case .parameterClause(let clause):
            return Set(
                clause.parameters.compactMap { parameter in
                    let value = cleanName((parameter.secondName ?? parameter.firstName).text)
                    return value == "_" ? nil : value
                })
        }
    }

    func addFunction(_ input: FunctionDeclarationInput) {
        let owner = directOwner(of: input.ownerAnchor, module: source.module)
        let names = parameterNames(input)
        let visitor = BodyVisitor(parameters: names, sourceLines: sourceLines)
        visitor.walk(input.statements)
        let ownerProperties =
            owner.map { key in
                types.filter { $0.key == key }.reduce(into: Set<String>()) {
                    $0.formUnion($1.propertyNames)
                }
            } ?? []
        let effectVisitor = EffectVisitor(
            parameters: names, ownerProperties: ownerProperties, sourceLines: sourceLines,
            isTestSource: isTestSource)
        recordInoutParameters(input.parameters, with: effectVisitor)
        effectVisitor.walk(input.statements)
        var functionRiskFacts = effectVisitor.riskFacts
        functionRiskFacts.append(
            contentsOf: declarationRiskFacts(for: input.node, name: input.name))
        functionRiskFacts.append(contentsOf: unsafeParameterRiskFacts(in: input.parameters))
        let labels = input.parameters.map { cleanName($0.firstName.text) + ":" }.joined()
        let prefix = owner?.displayName ?? source.module
        functions.append(
            FunctionFacts(
                name: "\(prefix).\(input.name)(\(labels))", kind: input.kind, owner: owner,
                location: sourceLines.location(input.node),
                codeLines: sourceLines.codeLines(input.statements).count,
                complexity: visitor.complexity,
                cognitiveComplexity: visitor.cognitiveComplexity,
                maxNestingDepth: visitor.maxNestingDepth,
                parameters: input.parameters.count, bareReferences: visitor.bareReferences,
                explicitSelfReferences: visitor.explicitSelfReferences,
                shadowedNames: visitor.shadowedNames,
                accessLevel: accessLevel(of: input.node), effectFacts: effectVisitor.effectFacts,
                compositionFacts: effectVisitor.compositionFacts, callSites: visitor.callSites,
                riskFacts: functionRiskFacts
            ))
    }

    private var isTestSource: Bool {
        let components = source.path.split(separator: "/").map(String.init)
        return source.module.hasSuffix("Tests") || source.module.hasSuffix("Test")
            || components.contains("Tests") || components.contains { $0.hasSuffix("Tests") }
            || source.path.hasSuffix("Tests.swift")
    }

    private func parameterNames(_ input: FunctionDeclarationInput) -> Set<String> {
        Set(
            input.parameters.compactMap { parameter -> String? in
                let value = cleanName((parameter.secondName ?? parameter.firstName).text)
                return value == "_" ? nil : value
            }
        ).union(input.implicitNames)
    }

    private func recordInoutParameters(
        _ parameters: FunctionParameterListSyntax, with visitor: EffectVisitor
    ) {
        for parameter in parameters {
            guard
                parameter.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    .hasPrefix("inout ")
            else {
                continue
            }
            let value = cleanName((parameter.secondName ?? parameter.firstName).text)
            if value != "_" {
                visitor.recordInoutParameter(
                    name: value, location: sourceLines.location(parameter))
            }
        }
    }

    func declarationRiskFacts(for node: Syntax, name: String) -> [SwiftRiskFact] {
        var facts: [SwiftRiskFact] = []
        let attributes = attributeNames(of: node)
        let inherited = inheritedTypes(of: node)
        if !attributes.isDisjoint(with: ["MainActor", "globalActor", "GlobalActor"]) {
            facts.append(
                SwiftRiskFact(
                    category: .globalActorIsolation,
                    detail: "global actor annotation on \(name)",
                    location: sourceLines.location(node)
                )
            )
        }
        if inherited.contains(where: isUncheckedSendableConformance) {
            facts.append(
                SwiftRiskFact(
                    category: .uncheckedSendable,
                    detail: "@unchecked Sendable on \(name)",
                    location: sourceLines.location(node)
                )
            )
        } else if inherited.contains(where: isSendableConformance) {
            facts.append(
                SwiftRiskFact(
                    category: .sendableConformance,
                    detail: "Sendable conformance on \(name)",
                    location: sourceLines.location(node),
                    confidence: .measuredSyntax
                )
            )
        }
        if hasModifier(node, named: "nonisolated") {
            facts.append(
                SwiftRiskFact(
                    category: .nonisolatedDeclaration,
                    detail: "nonisolated declaration \(name)",
                    location: sourceLines.location(node)
                )
            )
        }
        return facts
    }

    func unsafeParameterRiskFacts(in parameters: FunctionParameterListSyntax)
        -> [SwiftRiskFact]
    {
        parameters.compactMap { parameter in
            guard containsUnsafeStandardLibraryType(parameter.type) else { return nil }
            return SwiftRiskFact(
                category: .unsafeEscapeHatch,
                detail:
                    "unsafe parameter \(cleanName((parameter.secondName ?? parameter.firstName).text))",
                location: sourceLines.location(parameter)
            )
        }
    }
}
