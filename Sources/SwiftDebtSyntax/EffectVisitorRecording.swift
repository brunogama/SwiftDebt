import SwiftDebtCore
import SwiftSyntax

extension EffectVisitor {
    func recordComposition(_ node: FunctionCallExprSyntax) {
        if let operation = compositionOperation(node) {
            compositionFacts.append(
                FunctionalCompositionFact(
                    operation: operation,
                    location: sourceLines.location(node),
                    closureHasSideEffects: callContainsEffectfulClosure(node)))
        }
    }

    func recordCallRisk(_ node: FunctionCallExprSyntax) {
        guard let name = expressionName(node.calledExpression) else { return }
        if isTaskCreation(name) {
            riskFacts.append(
                SwiftRiskFact(
                    category: .unstructuredTask, detail: "unstructured task \(name)",
                    location: sourceLines.location(node)))
        }
        let containsUnsafeType = name.split(separator: ".").contains {
            isUnsafeStandardLibraryTypeName(String($0))
        }
        if containsUnsafeType {
            riskFacts.append(
                SwiftRiskFact(
                    category: .unsafeEscapeHatch,
                    detail: "unsafe standard-library call \(name)",
                    location: sourceLines.location(node)))
        }
        if ["fatalError", "preconditionFailure", "assertionFailure"].contains(lastComponent(name)) {
            riskFacts.append(
                SwiftRiskFact(
                    category: .errorTermination,
                    detail: "failure termination call \(name)",
                    location: sourceLines.location(node),
                    confidence: .measuredSyntax
                )
            )
        }
        if isTestSource && isTestSynchronizationCall(name) {
            riskFacts.append(
                SwiftRiskFact(
                    category: .testSynchronization,
                    detail: "test synchronization call \(name)",
                    location: sourceLines.location(node),
                    confidence: .measuredSyntax
                )
            )
        }
    }

    private func isTestSynchronizationCall(_ name: String) -> Bool {
        let last = lastComponent(name)
        return ["sleep", "usleep", "waitForExpectations", "wait"].contains(last)
            || name == "Task.sleep" || name.hasSuffix(".sleep")
    }

    func recordMutation(_ node: FunctionCallExprSyntax) {
        if let name = expressionName(node.calledExpression),
            mutatingCalls.contains(lastComponent(name))
        {
            effectFacts.append(
                SyntaxEffectFact(
                    category: .mutation, detail: "mutating call \(name)",
                    location: sourceLines.location(node), inClosure: closureDepth > 0))
        }
    }

    func recordInoutParameter(name: String, location: SwiftDebtCore.SourceLocation) {
        effectFacts.append(
            SyntaxEffectFact(
                category: .inoutMutation,
                detail: "inout parameter \(name)",
                location: location
            )
        )
        localNames.insert(name)
    }
}
