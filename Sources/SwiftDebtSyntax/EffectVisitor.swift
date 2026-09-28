import Foundation
import SwiftDebtCore
import SwiftSyntax

final class EffectVisitor: SyntaxVisitor {
    let sourceLines: SourceLines
    let ownerProperties: Set<String>
    let isTestSource: Bool
    let benignCompositionOperations: Set<String> = [
        "map", "compactMap", "filter", "reduce", "flatMap", "sorted",
    ]
    let mutatingCalls: Set<String> = [
        "append", "removeAll", "remove", "insert", "updateValue", "sort", "reverse", "toggle",
    ]
    var localNames: Set<String>
    var closureDepth = 0

    var effectFacts: [SyntaxEffectFact] = []
    var compositionFacts: [FunctionalCompositionFact] = []
    var riskFacts: [SwiftRiskFact] = []

    init(
        parameters: Set<String>, ownerProperties: Set<String>, sourceLines: SourceLines,
        isTestSource: Bool = false
    ) {
        self.localNames = parameters
        self.ownerProperties = ownerProperties
        self.sourceLines = sourceLines
        self.isTestSource = isTestSource
        super.init(viewMode: .sourceAccurate)
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
        recordAssignment(
            target: assignment.target, operatorText: assignment.operatorText,
            location: sourceLines.location(node))
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
        riskFacts.append(
            SwiftRiskFact(
                category: .isolationCrossing,
                detail: "await expression",
                location: sourceLines.location(node)
            )
        )
        return .visitChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind { recordTry(node) }
    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        recordCatch(node)
    }
    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        recordForceUnwrap(node)
    }
    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind { recordAs(node) }
    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        recordUnresolvedAs(node)
    }
    override func visit(_ node: ThrowStmtSyntax) -> SyntaxVisitorContinueKind { recordThrow(node) }
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        recordFunctionCall(node)
    }
    override func visit(_ node: UnsafeExprSyntax) -> SyntaxVisitorContinueKind {
        recordUnsafe(node)
    }
    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        recordClosure(node)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

}
