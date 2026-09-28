import SwiftDebtCore
import SwiftParser
import SwiftSyntax

/// A single observed occurrence of `@ObservedObject` used where `@StateObject`
/// would be correct (research #46, addendum J): the property is declared on a
/// `View` conformer and initialized in place, rather than received from
/// outside the view.
public struct ObservedObjectOwnedByViewFinding: Codable, Hashable, Sendable {
    public let viewName: String
    public let propertyName: String
    public let location: SwiftDebtCore.SourceLocation

    public init(
        viewName: String, propertyName: String, location: SwiftDebtCore.SourceLocation
    ) {
        self.viewName = viewName
        self.propertyName = propertyName
        self.location = location
    }
}

/// Deterministic, source-local detection for research #46: `@ObservedObject`
/// owned by the `View` that declares it. Ownership is decided purely from the
/// property's own syntactic shape - whether its declaration carries an
/// initializer expression - never from cross-file type resolution, matching
/// the addendum J guidance that this claim is cheap even before richer
/// capabilities exist.
///
/// A property fires when:
/// - it is declared directly in the member list of a `struct`/`class` that
///   conforms to `View` (directly, via `: View` in its inheritance clause),
/// - it carries an `@ObservedObject` attribute, and
/// - its `PatternBindingSyntax` has an initializer clause (`= ...`), meaning
///   the view constructs the observed object itself.
///
/// A property declared without an initializer (received via an `init`
/// parameter, or assigned from outside) never fires - there is nothing at the
/// declaration site indicating the view owns construction.
///
/// This claim is fully observable from syntax alone, so every detection - and
/// every source unit this rule inspects - reports `ObservationState.complete`.
public enum ObservedObjectOwnedByViewRule {
    public static let definition = RuleDefinition(
        identity: RuleIdentity("swiftui.observed-object-owned-by-view"),
        metadata: RuleMetadata(
            title: "@ObservedObject owned by the View that declares it",
            category: .uiFramework,
            provenance: [
                RuleProvenance(
                    researchItem: 46,
                    note: "Strong source-local rule when the property wrapper, "
                        + "initialization, and ownership conditions are observable "
                        + "(addendum J)."
                )
            ],
            supportState: .partial
        ),
        scope: .sourceUnit,
        mode: .deterministic,
        requirements: RuleRequirements([.syntax]),
        evidenceContract: EvidenceContract(
            required: .all([
                .fact(EvidenceRequirement(key: "observedObjectAttribute", kind: .syntax)),
                .fact(EvidenceRequirement(key: "viewConformance", kind: .syntax)),
                .fact(EvidenceRequirement(key: "inPlaceInitializer", kind: .syntax)),
            ])
        ),
        semanticRevision: 1
    )

    /// Detects the finding across a single source unit. Purely syntactic, so
    /// this never degrades below `ObservationState.complete`.
    public static func detect(
        in source: SourceUnit
    ) -> (state: ObservationState, findings: [ObservedObjectOwnedByViewFinding]) {
        let tree = Parser.parse(source: source.content)
        let converter = SourceLocationConverter(fileName: source.path, tree: tree)
        let sourceLines = SourceLines(file: source.path, converter: converter)
        let visitor = ObservedObjectOwnedByViewVisitor(sourceLines: sourceLines)
        visitor.walk(tree)
        return (.complete, visitor.findings)
    }
}

private final class ObservedObjectOwnedByViewVisitor: SyntaxVisitor {
    let sourceLines: SourceLines
    var findings: [ObservedObjectOwnedByViewFinding] = []

    init(sourceLines: SourceLines) {
        self.sourceLines = sourceLines
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(
            name: cleanName(node.name.text),
            inheritanceClause: node.inheritanceClause,
            members: node.memberBlock.members
        )
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        collect(
            name: cleanName(node.name.text),
            inheritanceClause: node.inheritanceClause,
            members: node.memberBlock.members
        )
        return .visitChildren
    }

    private func collect(
        name: String,
        inheritanceClause: InheritanceClauseSyntax?,
        members: MemberBlockItemListSyntax
    ) {
        guard conformsToView(inheritanceClause) else { return }
        for member in members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard hasObservedObjectAttribute(variable) else { continue }
            for binding in variable.bindings {
                guard binding.initializer != nil else { continue }
                guard let propertyName = bindingNames(binding.pattern).min() else { continue }
                findings.append(
                    ObservedObjectOwnedByViewFinding(
                        viewName: name,
                        propertyName: propertyName,
                        location: sourceLines.location(variable)
                    )
                )
            }
        }
    }

    private func conformsToView(_ inheritanceClause: InheritanceClauseSyntax?) -> Bool {
        guard let inheritanceClause else { return false }
        return inheritanceClause.inheritedTypes.contains { inherited in
            typeName(inherited.type) == "View"
        }
    }

    private func hasObservedObjectAttribute(_ node: VariableDeclSyntax) -> Bool {
        node.attributes.contains { attribute in
            guard case .attribute(let attribute) = attribute else { return false }
            return typeName(attribute.attributeName) == "ObservedObject"
        }
    }
}
