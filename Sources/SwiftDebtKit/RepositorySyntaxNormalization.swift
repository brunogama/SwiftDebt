import SwiftSyntax

struct NormalizedTokenSequence: Hashable, Comparable, Sendable {
    let tokens: [String]

    var canonicalValue: String {
        tokens.map { "\($0.utf8.count):\($0)" }.joined()
    }

    var displayValue: String {
        guard let first = tokens.first else { return "" }
        return tokens.dropFirst().reduce(first) { result, token in
            let separator = needsTokenSeparator(result.last, token.first) ? " " : ""
            return result + separator + token
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.tokens.lexicographicallyPrecedes(rhs.tokens)
    }

    private func needsTokenSeparator(_ left: Character?, _ right: Character?) -> Bool {
        guard let left, let right else { return false }
        if left.isLetter || left.isNumber || left == "_" {
            return right.isLetter || right.isNumber || right == "_"
        }
        let operatorCharacters = "/=-+!*%<>&|^?~"
        return operatorCharacters.contains(left) && operatorCharacters.contains(right)
    }
}

func normalizedIdentifier(_ value: String) -> String {
    value.hasPrefix("`") && value.hasSuffix("`") ? String(value.dropFirst().dropLast()) : value
}

func normalizedTokens(_ node: some SyntaxProtocol) -> NormalizedTokenSequence {
    NormalizedTokenSequence(
        tokens: node.tokens(viewMode: .sourceAccurate)
            .filter { $0.presence == .present }
            .map(\.text)
    )
}

func simpleDiscriminator(_ expression: ExprSyntax) -> NormalizedTokenSequence? {
    if expression.is(DeclReferenceExprSyntax.self) {
        return normalizedTokens(expression)
    }
    if let member = expression.as(MemberAccessExprSyntax.self),
        let base = member.base,
        simpleDiscriminator(base) != nil
    {
        return normalizedTokens(expression)
    }
    return nil
}

func nominalScope(of node: Syntax, module: String) -> String {
    var names: [String] = []
    var parent = node.parent
    while let current = parent {
        if let value = current.as(ClassDeclSyntax.self) {
            names.insert(normalizedIdentifier(value.name.text), at: 0)
        } else if let value = current.as(StructDeclSyntax.self) {
            names.insert(normalizedIdentifier(value.name.text), at: 0)
        } else if let value = current.as(EnumDeclSyntax.self) {
            names.insert(normalizedIdentifier(value.name.text), at: 0)
        } else if let value = current.as(ActorDeclSyntax.self) {
            names.insert(normalizedIdentifier(value.name.text), at: 0)
        } else if let value = current.as(ExtensionDeclSyntax.self) {
            names.insert(normalizedTokens(value.extendedType).displayValue, at: 0)
        }
        parent = current.parent
    }
    return ([module] + names).joined(separator: ".")
}

func hasCallableAncestor(_ node: Syntax) -> Bool {
    var parent = node.parent
    while let current = parent {
        if current.is(FunctionDeclSyntax.self) || current.is(InitializerDeclSyntax.self)
            || current.is(SubscriptDeclSyntax.self) || current.is(AccessorDeclSyntax.self)
            || current.is(ClosureExprSyntax.self)
        {
            return true
        }
        parent = current.parent
    }
    return false
}

func isTypeProperty(_ variable: VariableDeclSyntax) -> Bool {
    variable.modifiers.contains { modifier in
        modifier.name.text == "static" || modifier.name.text == "class"
    }
}

func isStoredProperty(_ binding: PatternBindingSyntax) -> Bool {
    guard let block = binding.accessorBlock else { return true }
    switch block.accessors {
    case .getter:
        return false
    case .accessors(let accessors):
        return accessors.allSatisfy {
            $0.accessorSpecifier.text == "willSet" || $0.accessorSpecifier.text == "didSet"
        }
    }
}
