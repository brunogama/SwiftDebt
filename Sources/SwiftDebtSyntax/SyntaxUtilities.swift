import SwiftDebtCore
import SwiftSyntax

func cleanName(_ text: String) -> String {
    text.hasPrefix("`") && text.hasSuffix("`") ? String(text.dropFirst().dropLast()) : text
}

func nominalName(_ node: Syntax) -> String? {
    if let value = node.as(ClassDeclSyntax.self) { return cleanName(value.name.text) }
    if let value = node.as(StructDeclSyntax.self) { return cleanName(value.name.text) }
    if let value = node.as(EnumDeclSyntax.self) { return cleanName(value.name.text) }
    if let value = node.as(ActorDeclSyntax.self) { return cleanName(value.name.text) }
    if let value = node.as(ExtensionDeclSyntax.self) { return typeName(value.extendedType) }
    return nil
}

func typeName(_ node: TypeSyntax) -> String? {
    if let identifier = node.as(IdentifierTypeSyntax.self) { return cleanName(identifier.name.text) }
    if let member = node.as(MemberTypeSyntax.self), let base = typeName(member.baseType) {
        return base + "." + cleanName(member.name.text)
    }
    if let attributed = node.as(AttributedTypeSyntax.self) { return typeName(attributed.baseType) }
    return nil
}

private let unsafeStandardLibraryTypeNames: Set<String> = [
    "AutoreleasingUnsafeMutablePointer",
    "UnsafeBufferPointer",
    "UnsafeContinuation",
    "UnsafeMutableBufferPointer",
    "UnsafeMutablePointer",
    "UnsafeMutableRawBufferPointer",
    "UnsafeMutableRawPointer",
    "UnsafePointer",
    "UnsafeRawBufferPointer",
    "UnsafeRawPointer",
    "UnsafeThrowingContinuation"
]

func isUnsafeStandardLibraryTypeName(_ name: String) -> Bool {
    guard let component = name.split(separator: ".").last else { return false }
    return unsafeStandardLibraryTypeNames.contains(String(component))
}

func containsUnsafeStandardLibraryType(_ type: TypeSyntax) -> Bool {
    let visitor = UnsafeTypeVisitor()
    visitor.walk(type)
    return visitor.found
}

private final class UnsafeTypeVisitor: SyntaxVisitor {
    var found = false

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        if isUnsafeStandardLibraryTypeName(cleanName(node.name.text)) { found = true }
        return found ? .skipChildren : .visitChildren
    }
}

func expressionName(_ node: ExprSyntax) -> String? {
    if let reference = node.as(DeclReferenceExprSyntax.self) { return cleanName(reference.baseName.text) }
    if let member = node.as(MemberAccessExprSyntax.self), let base = member.base,
        let prefix = expressionName(base)
    {
        return prefix + "." + cleanName(member.declName.baseName.text)
    }
    if let special = node.as(GenericSpecializationExprSyntax.self) { return expressionName(special.expression) }
    return nil
}

func isCallableBoundary(_ node: Syntax) -> Bool {
    node.is(FunctionDeclSyntax.self) || node.is(InitializerDeclSyntax.self)
        || node.is(DeinitializerDeclSyntax.self) || node.is(AccessorDeclSyntax.self)
        || node.is(SubscriptDeclSyntax.self) || node.is(ClosureExprSyntax.self)
}

func qualifiedName(of node: Syntax, ownName: String) -> String {
    var parts = [ownName]
    var parent = node.parent
    while let current = parent {
        if let name = nominalName(current) { parts.insert(name, at: 0) }
        if isCallableBoundary(current) {
            // Prevent a local type from colliding with a real nested type.
            parts.insert("<local@\(current.positionAfterSkippingLeadingTrivia.utf8Offset)>", at: 0)
        }
        parent = current.parent
    }
    return parts.joined(separator: ".")
}

func directOwner(of node: Syntax, module: String) -> TypeKey? {
    var parent = node.parent
    while let current = parent {
        if isCallableBoundary(current) || current.is(ProtocolDeclSyntax.self) { return nil }
        if let name = nominalName(current) {
            return TypeKey(module: module, name: qualifiedName(of: current, ownName: name))
        }
        parent = current.parent
    }
    return nil
}

final class PatternNames: SyntaxVisitor {
    var names: Set<String> = []
    init() { super.init(viewMode: .sourceAccurate) }
    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        let name = cleanName(node.identifier.text)
        if name != "_" { names.insert(name) }
        return .skipChildren
    }
}

func bindingNames(_ pattern: PatternSyntax) -> Set<String> {
    let visitor = PatternNames()
    visitor.walk(pattern)
    return visitor.names
}

struct SourceLines {
    let file: String
    let converter: SourceLocationConverter

    func location(_ node: some SyntaxProtocol) -> SwiftDebtCore.SourceLocation {
        let value = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        return SwiftDebtCore.SourceLocation(file: file, line: value.line, column: value.column)
    }

    func codeLines(_ node: some SyntaxProtocol) -> [CodeLine] {
        var fragments: [Int: [String]] = [:]
        for token in node.tokens(viewMode: .sourceAccurate) {
            guard token.presence == .present, !token.text.isEmpty else { continue }
            var line = converter.location(for: token.positionAfterSkippingLeadingTrivia).line
            let bytes = Array(token.text.utf8)
            var part: [UInt8] = []
            var index = 0
            func record() {
                guard part.contains(where: { $0 != 32 && $0 != 9 }) else { return }
                let text = String(decoding: part, as: UTF8.self)
                fragments[line, default: []].append("\(part.count):\(text)")
            }
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 10 || byte == 13 {
                    record()
                    part.removeAll(keepingCapacity: true)
                    if byte == 13 && index + 1 < bytes.count && bytes[index + 1] == 10 { index += 1 }
                    line += 1
                } else {
                    part.append(byte)
                }
                index += 1
            }
            record()
        }
        return fragments.keys.sorted().map {
            CodeLine(number: $0, signature: fragments[$0, default: []].joined(separator: "|"))
        }
    }
}
