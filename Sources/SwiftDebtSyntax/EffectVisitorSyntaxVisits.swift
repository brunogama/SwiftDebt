import SwiftDebtCore
import SwiftSyntax

extension EffectVisitor {
    func recordTry(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        effectFacts.append(
            SyntaxEffectFact(
                category: .throwingEffect,
                detail: "try expression",
                location: sourceLines.location(node),
                inClosure: closureDepth > 0
            )
        )
        if let marker = node.questionOrExclamationMark?.text {
            let category: SwiftRiskCategory = marker == "?" ? .errorSwallowing : .errorTermination
            riskFacts.append(
                SwiftRiskFact(
                    category: category,
                    detail: "try\(marker) expression",
                    location: sourceLines.location(node),
                    confidence: .measuredSyntax
                )
            )
        }
        return .visitChildren
    }

    func recordCatch(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        if node.body.statements.isEmpty {
            riskFacts.append(
                SwiftRiskFact(
                    category: .errorSwallowing,
                    detail: "empty catch clause",
                    location: sourceLines.location(node),
                    confidence: .measuredSyntax
                )
            )
        }
        return .visitChildren
    }

    func recordForceUnwrap(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        riskFacts.append(
            SwiftRiskFact(
                category: .errorTermination,
                detail: "force unwrap expression",
                location: sourceLines.location(node),
                confidence: .measuredSyntax
            )
        )
        return .visitChildren
    }

    func recordAs(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        recordForcedCastIfNeeded(marker: node.questionOrExclamationMark, node: node)
        return .visitChildren
    }

    func recordUnresolvedAs(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        recordForcedCastIfNeeded(marker: node.questionOrExclamationMark, node: node)
        return .visitChildren
    }

    private func recordForcedCastIfNeeded(marker: TokenSyntax?, node: some SyntaxProtocol) {
        guard marker?.text == "!" else { return }
        riskFacts.append(
            SwiftRiskFact(
                category: .errorTermination,
                detail: "forced cast expression",
                location: sourceLines.location(node),
                confidence: .measuredSyntax
            )
        )
    }

    func recordThrow(_ node: ThrowStmtSyntax) -> SyntaxVisitorContinueKind {
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

    func recordFunctionCall(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        recordComposition(node)
        recordCallRisk(node)
        recordMutation(node)
        return .visitChildren
    }

    func recordUnsafe(_ node: UnsafeExprSyntax) -> SyntaxVisitorContinueKind {
        riskFacts.append(
            SwiftRiskFact(
                category: .unsafeEscapeHatch,
                detail: "unsafe expression",
                location: sourceLines.location(node),
                confidence: .measuredSyntax
            )
        )
        return .visitChildren
    }

    func recordClosure(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
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
}
