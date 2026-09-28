import SwiftSyntax

func attributeNames(of node: Syntax) -> Set<String> {
    guard let declaration = node.asProtocol(WithAttributesSyntax.self) else { return [] }
    return Set(
        declaration.attributes.compactMap { element in
            guard case .attribute(let attribute) = element else { return nil }
            return typeName(attribute.attributeName)
        })
}

func accessLevel(of node: Syntax) -> String? {
    ["open", "public", "package"].first { hasModifier(node, named: $0) }
}

func hasModifier(_ node: Syntax, named name: String) -> Bool {
    node.asProtocol(WithModifiersSyntax.self)?.modifiers.contains {
        cleanName($0.name.text) == name
    } == true
}

func hasAnyModifier(_ node: Syntax, named names: Set<String>) -> Bool {
    node.asProtocol(WithModifiersSyntax.self)?.modifiers.contains {
        names.contains(cleanName($0.name.text))
    } == true
}

func inheritedTypes(of node: Syntax) -> [TypeSyntax] {
    node.asProtocol(DeclGroupSyntax.self)?.inheritanceClause?.inheritedTypes.map(\.type) ?? []
}

func isSendableConformance(_ type: TypeSyntax) -> Bool {
    typeName(type)?.split(separator: ".").last == "Sendable"
}

func isUncheckedSendableConformance(_ type: TypeSyntax) -> Bool {
    guard isSendableConformance(type), let attributed = type.as(AttributedTypeSyntax.self) else {
        return false
    }
    return attributeNames(of: Syntax(attributed)).contains("unchecked")
}
