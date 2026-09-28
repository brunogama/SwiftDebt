package struct TypeKey: Hashable, Sendable {
    package let module: String
    package let name: String
    package var displayName: String { "\(module).\(name)" }

    package init(module: String, name: String) {
        self.module = module
        self.name = name
    }
}

package struct TypeFragment: Sendable {
    package let key: TypeKey
    package let kind: String
    package let isExtension: Bool
    package let location: SourceLocation
    package let codeLines: Int
    package let propertyNames: Set<String>
    package let referencedTypes: Set<String>
    package let importedModules: Set<String>

    package init(
        key: TypeKey, kind: String, isExtension: Bool, location: SourceLocation,
        codeLines: Int, propertyNames: Set<String>, referencedTypes: Set<String>,
        importedModules: Set<String> = []
    ) {
        self.key = key
        self.kind = kind
        self.isExtension = isExtension
        self.location = location
        self.codeLines = codeLines
        self.propertyNames = propertyNames
        self.referencedTypes = referencedTypes
        self.importedModules = importedModules
    }
}

package enum CallableKind: Sendable {
    /// `func`, `init`, `deinit`.
    case method
    /// Property or subscript accessor body (`get`, `set`, `willSet`, `didSet`, ...).
    case accessor
}

package enum SyntaxEvidenceConfidence: String, Codable, Sendable {
    case measuredSyntax
    case heuristic
}

package enum SyntaxEffectCategory: String, Codable, CaseIterable, Sendable {
    case mutation
    case inoutMutation
    case propertyWrite
    case globalOrStaticState
    case asyncEffect
    case throwingEffect
    case closureEffect
}

package enum SwiftRiskCategory: String, Codable, CaseIterable, Sendable {
    case isolationCrossing
    case actorIsolation
    case globalActorIsolation
    case sendableConformance
    case uncheckedSendable
    case unstructuredTask
    case nonisolatedDeclaration
    case mutableSharedState
    case unsafeEscapeHatch
    /// An error is discarded instead of being observed or propagated.
    case errorSwallowing
    /// A failure path can terminate the process instead of returning an error.
    case errorTermination
    /// A test waits on wall-clock time or a polling primitive instead of a condition.
    case testSynchronization
}

package struct SyntaxEffectFact: Codable, Hashable, Sendable {
    package let category: SyntaxEffectCategory
    package let detail: String
    package let location: SourceLocation
    package let confidence: SyntaxEvidenceConfidence
    package let inClosure: Bool

    package init(
        category: SyntaxEffectCategory,
        detail: String,
        location: SourceLocation,
        confidence: SyntaxEvidenceConfidence = .measuredSyntax,
        inClosure: Bool = false
    ) {
        self.category = category
        self.detail = detail
        self.location = location
        self.confidence = confidence
        self.inClosure = inClosure
    }
}

package struct SwiftRiskFact: Codable, Hashable, Sendable {
    package let category: SwiftRiskCategory
    package let detail: String
    package let location: SourceLocation
    package let confidence: SyntaxEvidenceConfidence

    package init(
        category: SwiftRiskCategory,
        detail: String,
        location: SourceLocation,
        confidence: SyntaxEvidenceConfidence = .heuristic
    ) {
        self.category = category
        self.detail = detail
        self.location = location
        self.confidence = confidence
    }
}

package struct FunctionalCompositionFact: Codable, Hashable, Sendable {
    package let operation: String
    package let location: SourceLocation
    package let closureHasSideEffects: Bool
    package let confidence: SyntaxEvidenceConfidence

    package init(
        operation: String,
        location: SourceLocation,
        closureHasSideEffects: Bool,
        confidence: SyntaxEvidenceConfidence = .measuredSyntax
    ) {
        self.operation = operation
        self.location = location
        self.closureHasSideEffects = closureHasSideEffects
        self.confidence = confidence
    }
}
