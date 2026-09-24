import SwiftDebtCore
import SwiftSyntax

public struct ForceTryRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt"),
        id: RuleID(validated: "force-try")
    )
    public static let metadata = RuleMetadata(
        name: "Force try",
        defaultSeverity: .warning,
        remediation: "Handle or propagate the error instead of forcing the throwing expression."
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports every syntactic try! occurrence in a successfully parsed source tree, including all #if branches.",
        rationale:
            "A force try traps when its expression throws. Syntax-only analysis does not evaluate conditional compilation."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        let visitor = ForceTryVisitor(emit: emit)
        visitor.walk(context.sourceFile)
    }
}

private final class ForceTryVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if let marker = node.questionOrExclamationMark, marker.tokenKind == .exclamationMark {
            emit(
                at: marker,
                message: "This try! traps if the expression throws; handle or propagate the error."
            )
        }
        return .visitChildren
    }
}
