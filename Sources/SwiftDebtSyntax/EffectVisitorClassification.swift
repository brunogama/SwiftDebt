import Foundation
import SwiftDebtCore
import SwiftSyntax

extension EffectVisitor {
    func recordAssignment(
        target: String, operatorText: String, location: SwiftDebtCore.SourceLocation
    ) {
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

    func isPropertyTarget(_ target: String) -> Bool {
        target.hasPrefix("self.") || target.hasPrefix("Self.") || target.contains(".")
            || ownerProperties.contains(firstIdentifier(target))
    }

    func isGlobalOrStaticTarget(_ target: String) -> Bool {
        let first = firstIdentifier(target)
        if target.hasPrefix("Self.") || target.contains(".shared") || target.contains("Defaults") {
            return true
        }
        if let scalar = first.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(scalar) {
            return true
        }
        return !first.isEmpty && !localNames.contains(first) && !ownerProperties.contains(first)
            && first != "self" && first != "Self"
    }

    func compositionOperation(_ node: FunctionCallExprSyntax) -> String? {
        let name =
            expressionName(node.calledExpression)
            ?? node.calledExpression.as(MemberAccessExprSyntax.self).map {
                cleanName($0.declName.baseName.text)
            }
        guard let name else { return nil }
        let operation = lastComponent(name)
        return benignCompositionOperations.contains(operation) ? operation : nil
    }

    func callContainsEffectfulClosure(_ node: FunctionCallExprSyntax) -> Bool {
        node.arguments.contains { argument in
            guard let closure = argument.expression.as(ClosureExprSyntax.self) else { return false }
            return closureTextLooksEffectful(closure.description)
        } || node.trailingClosure.map { closureTextLooksEffectful($0.description) } ?? false
    }

    func closureTextLooksEffectful(_ text: String) -> Bool {
        assignment(in: text) != nil || text.contains("try ") || text.contains("await ")
            || text.contains("&")
    }

    func assignment(in text: String) -> (target: String, operatorText: String)? {
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

    func isComparisonOrArrow(_ text: String, at range: Range<String.Index>) -> Bool {
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

    func firstIdentifier(_ text: String) -> String {
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

    func lastComponent(_ text: String) -> String {
        text.split(separator: ".").last.map(String.init) ?? text
    }

    func isTaskCreation(_ text: String) -> Bool {
        text == "Task" || text == "Task.detached"
    }

    func compact(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: {
            $0.isWhitespace
        }).joined(separator: " ")
    }
}
