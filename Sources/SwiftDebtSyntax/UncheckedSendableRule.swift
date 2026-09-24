import SwiftDebtCore
import SwiftSyntax

public struct UncheckedSendableRule: DebtRule {
    public static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.concurrency"),
        id: RuleID(validated: "unchecked-sendable")
    )
    public static let metadata = RuleMetadata(
        name: "Unchecked Sendable conformance",
        defaultSeverity: .information,
        remediation: "Review and document how the conforming type enforces thread safety."
    )
    public static let contract = RuleContract(
        semanticRevision: .initial,
        semantics:
            "Reports inherited-type syntax spelled @unchecked Sendable, including every #if branch in a successfully parsed source tree.",
        rationale:
            "@unchecked disables compiler enforcement for the conformance. This syntax-only observation does not bind the Sendable name, evaluate conditional compilation, or prove a race."
    )

    public init() {}

    public func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        UncheckedSendableVisitor(emit: emit).walk(context.sourceFile)
    }
}

private final class UncheckedSendableVisitor: SyntaxVisitor {
    private let emit: DetectionEmitter

    init(emit: DetectionEmitter) {
        self.emit = emit
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
        guard
            let attributedType = node.type.as(AttributedTypeSyntax.self),
            isSendableSpelling(attributedType.baseType),
            let unchecked = attributedType.attributes.compactMap({ $0.as(AttributeSyntax.self) })
                .first(where: { $0.attributeName.trimmedDescription == "unchecked" })
        else { return .visitChildren }

        emit(
            at: unchecked.atSign,
            message:
                "This @unchecked Sendable conformance disables compiler enforcement; review the type's thread-safety assumptions."
        )
        return .visitChildren
    }

    private func isSendableSpelling(_ type: TypeSyntax) -> Bool {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text == "Sendable"
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text == "Sendable"
        }
        return false
    }
}
