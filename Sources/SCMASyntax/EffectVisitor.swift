import Foundation
import SCMACore
import SwiftSyntax

final class EffectVisitor: SyntaxVisitor {
    private let sourceLines: SourceLines
    private let ownerProperties: Set<String>
    private let benignCompositionOperations: Set<String> = ["map", "compactMap", "filter", "reduce", "flatMap", "sorted"]
    private let mutatingCalls: Set<String> = ["append", "removeAll", "remove", "insert", "updateValue", "sort", "reverse", "toggle"]
    private var localNames: Set<String>
    private var closureDepth = 0

    var effectFacts: [SyntaxEffectFact] = []
    var compositionFacts: [FunctionalCompositionFact] = []

    init(parameters: Set<String>, ownerProperties: Set<String>, sourceLines: SourceLines) {
        self.localNames = parameters
        self.ownerProperties = ownerProperties
        self.sourceLines = sourceLines
        super.init(viewMode: .sourceAccurate)
    }

    func recordInoutParameter(name: String, location: SCMACore.SourceLocation) {
        effectFacts.append(
            SyntaxEffectFact(
                category: .inoutMutation,
                detail: "inout parameter \(name)",
                location: location
            )
        )
        localNames.insert(name)
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        if let initializer = node.initializer { walk(initializer) }
        for name in bindingNames(node.pattern) { localNames.insert(name) }
        if let accessorBlock = node.accessorBlock { walk(accessorBlock) }
        return .skipChildren
    }

    override func visit(_ node: OptionalBindingConditionSyntax) -> SyntaxVisitorContinueKind {
        if let initializer = node.initializer { walk(initializer) }
        walk(node.pattern)
        return .skipChildren
    }

    override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
        let name = cleanName(node.identifier.text)
        if name != "_" { localNames.insert(name) }
        return .skipChildren
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        walk(node.pattern)
        walk(node.sequence)
        walk(node.body)
        return .skipChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        guard let assignment = assignment(in: node.description) else { return .visitChildren }
        recordAssignment(target: assignment.target, operatorText: assignment.operatorText, location: sourceLines.location(node))
        return .visitChildren
    }

    override func visit(_ node: PrefixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.text == "&" {
            effectFacts.append(
                SyntaxEffectFact(
                    category: .inoutMutation,
                    detail: "inout argument \(compact(node.expression.description))",
                    location: sourceLines.location(node),
                    inClosure: closureDepth > 0
                )
            )
        }
        return .visitChildren
    }

    override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        effectFacts.append(
            SyntaxEffectFact(
                category: .asyncEffect,
                detail: "await expression",
                location: sourceLines.location(node),
                inClosure: closureDepth > 0
            )
        )
        return .visitChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        effectFacts.append(
            SyntaxEffectFact(
                category: .throwingEffect,
                detail: "try expression",
                location: sourceLines.location(node),
                inClosure: closureDepth > 0
            )
        )
        return .visitChildren
    }

    override func visit(_ node: ThrowStmtSyntax) -> SyntaxVisitorContinueKind {
        effectFacts.append(
            SyntaxEffectFact(
                category: .throwingEffect,
                detail: "throw statement",
                location: sourceLines.location(node),
                inClosure: closureDepth > 0
            )
        )
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let operation = compositionOperation(node) {
            compositionFacts.append(
                FunctionalCompositionFact(
                    operation: operation,
                    location: sourceLines.location(node),
                    closureHasSideEffects: callContainsEffectfulClosure(node)
                )
            )
        }
        if let name = expressionName(node.calledExpression), mutatingCalls.contains(lastComponent(name)) {
            effectFacts.append(
                SyntaxEffectFact(
                    category: .mutation,
                    detail: "mutating call \(name)",
                    location: sourceLines.location(node),
                    inClosure: closureDepth > 0
                )
            )
        }
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        closureDepth += 1
        let before = effectFacts.count
        walk(node.statements)
        if effectFacts.count > before {
            effectFacts.append(
                SyntaxEffectFact(
                    category: .closureEffect,
                    detail: "effectful closure",
                    location: sourceLines.location(node),
                    inClosure: true
                )
            )
        }
        closureDepth -= 1
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    private func recordAssignment(target: String, operatorText: String, location: SCMACore.SourceLocation) {
        let trimmed = compact(target)
        guard !trimmed.isEmpty else { return }
        effectFacts.append(
            SyntaxEffectFact(
                category: .mutation,
                detail: "\(trimmed) \(operatorText)",
                location: location,
                inClosure: closureDepth > 0
            )
        )
        if isPropertyTarget(trimmed) {
            effectFacts.append(
                SyntaxEffectFact(
                    category: .propertyWrite,
                    detail: "\(trimmed) \(operatorText)",
                    location: location,
                    inClosure: closureDepth > 0
                )
            )
        }
        if isGlobalOrStaticTarget(trimmed) {
            effectFacts.append(
                SyntaxEffectFact(
                    category: .globalOrStaticState,
                    detail: "\(trimmed) \(operatorText)",
                    location: location,
                    confidence: .heuristic,
                    inClosure: closureDepth > 0
                )
            )
        }
    }

    private func isPropertyTarget(_ target: String) -> Bool {
        target.hasPrefix("self.") || target.hasPrefix("Self.") || target.contains(".") || ownerProperties.contains(firstIdentifier(target))
    }

    private func isGlobalOrStaticTarget(_ target: String) -> Bool {
        let first = firstIdentifier(target)
        if target.hasPrefix("Self.") || target.contains(".shared") || target.contains("Defaults") { return true }
        if let scalar = first.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(scalar) { return true }
        return !first.isEmpty && !localNames.contains(first) && !ownerProperties.contains(first) && first != "self" && first != "Self"
    }

    private func compositionOperation(_ node: FunctionCallExprSyntax) -> String? {
        let name = expressionName(node.calledExpression)
            ?? node.calledExpression.as(MemberAccessExprSyntax.self).map { cleanName($0.declName.baseName.text) }
        guard let name else { return nil }
        let operation = lastComponent(name)
        return benignCompositionOperations.contains(operation) ? operation : nil
    }

    private func callContainsEffectfulClosure(_ node: FunctionCallExprSyntax) -> Bool {
        node.arguments.contains { argument in
            guard let closure = argument.expression.as(ClosureExprSyntax.self) else { return false }
            return closureTextLooksEffectful(closure.description)
        } || node.trailingClosure.map { closureTextLooksEffectful($0.description) } ?? false
    }

    private func closureTextLooksEffectful(_ text: String) -> Bool {
        assignment(in: text) != nil || text.contains("try ") || text.contains("await ") || text.contains("&")
    }

    private func assignment(in text: String) -> (target: String, operatorText: String)? {
        let operators = ["+=", "-=", "*=", "/=", "%=", "="]
        for operatorText in operators {
            guard let range = text.range(of: operatorText) else { continue }
            if operatorText == "=", isComparisonOrArrow(text, at: range) { continue }
            let target = String(text[..<range.lowerBound])
            if target.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("let ") { continue }
            return (target, operatorText)
        }
        return nil
    }

    private func isComparisonOrArrow(_ text: String, at range: Range<String.Index>) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if before == "=" || before == "!" || before == "<" || before == ">" { return true }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if after == "=" || after == ">" { return true }
        }
        return false
    }

    private func firstIdentifier(_ text: String) -> String {
        var result = ""
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty {
                break
            }
        }
        return cleanName(result)
    }

    private func lastComponent(_ text: String) -> String {
        text.split(separator: ".").last.map(String.init) ?? text
    }

    private func compact(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
