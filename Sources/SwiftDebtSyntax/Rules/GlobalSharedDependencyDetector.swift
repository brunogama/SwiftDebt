import SwiftDebtCore
import SwiftParser
import SwiftSyntax

/// Observed evidence for one candidate `architecture.global-shared-dependency`
/// binding (research item #3, addendum J). Carries the actual observed facts
/// (mutability, usage count) rather than a single confidence number, per
/// PRD FR-8.
public struct GlobalSharedDependencyEvidence: Codable, Hashable, Sendable {
    /// The type that owns the singleton-shaped binding (e.g. "Foo").
    public let singletonTypeName: String
    /// The binding's own name (e.g. "shared", "default", "sharedManager").
    public let bindingName: String
    /// Whether the owning type declares at least one mutable (`var`) stored
    /// property directly on itself.
    public let hasMutableStoredProperty: Bool
    /// Names of the mutable stored properties found (empty when
    /// `hasMutableStoredProperty` is `false`).
    public let mutablePropertyNames: Set<String>
    /// Count of `TypeName.bindingName` member-access sites found within the
    /// analyzed source unit (this rule is `.sourceUnit`-scoped; no
    /// cross-file resolution is attempted).
    public let usageCount: Int
    /// The threshold `usageCount` was compared against.
    public let usageThreshold: Int
    /// `hasMutableStoredProperty && usageCount >= usageThreshold`. A
    /// stateless/immutable singleton never fires regardless of how heavily
    /// it is used - the mutability gate is structural, not a threshold
    /// coincidence.
    public let fires: Bool
    /// Location of the singleton binding's declaration.
    public let location: SwiftDebtCore.SourceLocation

    public init(
        singletonTypeName: String,
        bindingName: String,
        hasMutableStoredProperty: Bool,
        mutablePropertyNames: Set<String>,
        usageCount: Int,
        usageThreshold: Int,
        location: SwiftDebtCore.SourceLocation
    ) {
        self.singletonTypeName = singletonTypeName
        self.bindingName = bindingName
        self.hasMutableStoredProperty = hasMutableStoredProperty
        self.mutablePropertyNames = mutablePropertyNames
        self.usageCount = usageCount
        self.usageThreshold = usageThreshold
        self.fires = hasMutableStoredProperty && usageCount >= usageThreshold
        self.location = location
    }
}

/// Heuristic (`.heuristic`/`.sourceUnit`) detector for
/// `architecture.global-shared-dependency`: a `static let`/`static var`
/// singleton-shaped binding whose owning type carries mutable stored state
/// and is referenced broadly within the analyzed source unit.
///
/// This is a plain, standalone detector - not a `RuleImplementation`
/// conformer. `RuleImplementation.Context`/`DetectionEmitter` are still
/// marker protocols with no concrete conformer anywhere in the repository
/// (confirmed against `R1R2CoexistenceTests`, whose own doc comments call
/// that wiring "future, separate work"), so wiring this detector to a real
/// `AnalysisContext`/`DetectionEmitter` is out of scope here.
public enum GlobalSharedDependencyDetector {
    /// Binding names accepted outright as singleton-shaped, without regard
    /// to the owning type's name.
    static let exactBindingNames: Set<String> = ["shared", "default", "instance"]

    /// Minimum distinct `TypeName.bindingName` usage sites within the
    /// analyzed source unit for a mutable singleton to be considered
    /// "reached broadly" rather than just a coincidental single call site.
    ///
    /// Rationale: 1 usage is often just the definition's own file
    /// referencing itself once, or a single call site that is not
    /// indicative of "global" reach; 2 could still be coincidental (e.g. one
    /// production call site plus one test). 3+ distinct usage sites is a
    /// defensible minimum signal of "used broadly" for a rule that is
    /// `.sourceUnit`-scoped and therefore cannot see usage in other files.
    public static let usageThreshold = 3

    /// Whether `name` is a singleton-shaped binding name: an exact match
    /// against `exactBindingNames`, or a `shared<Suffix>` name such as
    /// `sharedInstance`/`sharedManager` (the common Cocoa-derived
    /// convention of prefixing the accessor with "shared").
    static func isSingletonBindingName(_ name: String) -> Bool {
        if exactBindingNames.contains(name) { return true }
        guard name.hasPrefix("shared"), name.count > "shared".count else { return false }
        let suffixStart = name.index(name.startIndex, offsetBy: "shared".count)
        return name[suffixStart].isUppercase
    }

    public static func detect(in source: SourceUnit) -> [GlobalSharedDependencyEvidence] {
        let tree = Parser.parse(source: source.content)
        let converter = SourceLocationConverter(fileName: source.path, tree: tree)
        let sourceLines = SourceLines(file: source.path, converter: converter)

        let typeVisitor = SingletonTypeVisitor(module: source.module)
        typeVisitor.walk(tree)

        return typeVisitor.bindings.map { binding in
            let usageCount = countUsages(
                root: tree, typeName: binding.owner.name, bindingName: binding.name)
            return GlobalSharedDependencyEvidence(
                singletonTypeName: binding.owner.name,
                bindingName: binding.name,
                hasMutableStoredProperty: !binding.mutablePropertyNames.isEmpty,
                mutablePropertyNames: binding.mutablePropertyNames,
                usageCount: usageCount,
                usageThreshold: usageThreshold,
                location: sourceLines.location(binding.node)
            )
        }
    }

    private static func countUsages(
        root: SourceFileSyntax, typeName: String, bindingName: String
    ) -> Int {
        let visitor = SingletonUsageVisitor(typeName: typeName, bindingName: bindingName)
        visitor.walk(root)
        return visitor.count
    }
}

// MARK: - Catalog entry

/// The `architecture.global-shared-dependency` `RuleDefinition` (research
/// item #3, addendum J). There is no central "real rule" catalog/manifest
/// registration point yet: `Sources/SwiftDebtCore/RuleCatalog/Manifest/` only
/// has a YAML *parser and validator*, exercised solely by
/// `Tests/SwiftDebtCoreTests/Fixtures/RuleCatalogManifest/*.yaml` test
/// fixtures - no production manifest file exists to add this rule's entry
/// to. The definition is therefore colocated with its detector here, as the
/// task brief allows.
public enum GlobalSharedDependencyRule {
    public static let definition = RuleDefinition(
        identity: RuleIdentity("architecture.global-shared-dependency"),
        metadata: RuleMetadata(
            title: "Global shared dependency",
            category: .architecture,
            provenance: [RuleProvenance(researchItem: 3, note: "addendum J")],
            // `.partial`: the detector is a heuristic, syntax-only signal
            // (static-binding-name pattern matching, single-file mutability
            // and usage-count checks) that has not yet been validated
            // end-to-end against the full R2 acceptance corpus's fixture
            // set, so it does not yet warrant `.supported`. It is not
            // `.research` either: it is implemented and has fixture
            // coverage proving both the fire and no-fire path, just not the
            // full corpus.
            supportState: .partial
        ),
        scope: .sourceUnit,
        mode: .heuristic,
        // `.syntax`/`.symbols`/`.types` cover locating the singleton
        // binding, resolving its owning type, and reading that type's own
        // stored properties. `.metrics` is added because the usage-count
        // evidence fact below is declared with `EvidenceFactKind.metric`,
        // and `RuleCatalogValidator.requiredCapability(for:)` maps
        // `.metric` facts to the `.metrics` capability - so the
        // requirements set stays consistent with that cross-check even
        // though this definition isn't run through the validator here.
        requirements: RuleRequirements([.syntax, .symbols, .types, .metrics]),
        evidenceContract: EvidenceContract(
            required: .all([
                .fact(EvidenceRequirement(key: "singleton.mutableStoredProperty", kind: .syntax)),
                .fact(EvidenceRequirement(key: "singleton.usageCount", kind: .metric)),
            ])
        ),
        semanticRevision: 1
    )
}
