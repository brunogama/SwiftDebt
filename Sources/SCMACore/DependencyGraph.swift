public enum SwiftGraphNodeKind: String, Codable, Sendable {
    case module
    case type
    case callable
}

public struct SwiftGraphNode: Codable, Hashable, Sendable {
    public let id: String
    public let kind: SwiftGraphNodeKind
    public let module: String
    public let displayName: String
    public let location: SourceLocation?
    public let isTest: Bool

    public init(
        id: String,
        kind: SwiftGraphNodeKind,
        module: String,
        displayName: String,
        location: SourceLocation? = nil,
        isTest: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.module = module
        self.displayName = displayName
        self.location = location
        self.isTest = isTest
    }
}

public enum SwiftGraphEdgeKind: String, Codable, Sendable {
    case moduleDependency
    case typeReference
    case call
}

public enum SwiftGraphResolutionConfidence: String, Codable, Sendable {
    case resolvedSyntax
    case ambiguousSyntax
    case unresolvedSyntax
}

public struct SwiftGraphEdge: Codable, Hashable, Sendable {
    public let source: String
    public let target: String?
    public let targetCandidates: [String]
    public let kind: SwiftGraphEdgeKind
    public let unresolvedName: String?
    public let confidence: SwiftGraphResolutionConfidence
    public let location: SourceLocation
    public let isTestCaller: Bool
    public let note: String

    public init(
        source: String,
        target: String?,
        targetCandidates: [String] = [],
        kind: SwiftGraphEdgeKind,
        unresolvedName: String? = nil,
        confidence: SwiftGraphResolutionConfidence,
        location: SourceLocation,
        isTestCaller: Bool = false,
        note: String
    ) {
        self.source = source
        self.target = target
        self.targetCandidates = targetCandidates
        self.kind = kind
        self.unresolvedName = unresolvedName
        self.confidence = confidence
        self.location = location
        self.isTestCaller = isTestCaller
        self.note = note
    }
}

public struct CouplingRiskEvidence: Codable, Hashable, Sendable {
    public let entityID: String
    public let entityDisplayName: String
    public let entityKind: SwiftGraphNodeKind
    public let afferentCoupling: Int
    public let efferentCoupling: Int
    public let callerCount: Int
    public let productionCallerCount: Int
    public let testCallerCount: Int
    public let fanIn: Int
    public let fanOut: Int
    public let instability: Double?
    public let note: String

    public init(
        entityID: String,
        entityDisplayName: String,
        entityKind: SwiftGraphNodeKind,
        afferentCoupling: Int,
        efferentCoupling: Int,
        callerCount: Int,
        productionCallerCount: Int,
        testCallerCount: Int,
        fanIn: Int,
        fanOut: Int,
        instability: Double?,
        note: String
    ) {
        self.entityID = entityID
        self.entityDisplayName = entityDisplayName
        self.entityKind = entityKind
        self.afferentCoupling = afferentCoupling
        self.efferentCoupling = efferentCoupling
        self.callerCount = callerCount
        self.productionCallerCount = productionCallerCount
        self.testCallerCount = testCallerCount
        self.fanIn = fanIn
        self.fanOut = fanOut
        self.instability = instability
        self.note = note
    }
}

public struct CallGraphStatistics: Codable, Hashable, Sendable {
    public let nodeCount: Int
    public let edgeCount: Int
    public let resolvedEdgeCount: Int
    public let ambiguousEdgeCount: Int
    public let unresolvedEdgeCount: Int
    public let syntaxOnlyNote: String

    public init(
        nodeCount: Int,
        edgeCount: Int,
        resolvedEdgeCount: Int,
        ambiguousEdgeCount: Int,
        unresolvedEdgeCount: Int,
        syntaxOnlyNote: String
    ) {
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.resolvedEdgeCount = resolvedEdgeCount
        self.ambiguousEdgeCount = ambiguousEdgeCount
        self.unresolvedEdgeCount = unresolvedEdgeCount
        self.syntaxOnlyNote = syntaxOnlyNote
    }
}

public struct DependencyContext: Codable, Equatable, Sendable {
    public let entity: DebtEntity
    public let upstreamDependencies: [String]
    public let downstreamDependents: [String]
    public let evidence: [DebtEvidence]

    public init(
        entity: DebtEntity,
        upstreamDependencies: [String],
        downstreamDependents: [String],
        evidence: [DebtEvidence]
    ) {
        self.entity = entity
        self.upstreamDependencies = upstreamDependencies
        self.downstreamDependents = downstreamDependents
        self.evidence = evidence
    }
}

public struct SwiftDependencyGraph: Codable, Equatable, Sendable {
    public let nodes: [SwiftGraphNode]
    public let edges: [SwiftGraphEdge]
    public let couplingRisks: [CouplingRiskEvidence]
    public let dependencyContexts: [DependencyContext]
    public let statistics: CallGraphStatistics
    public let dot: String

    public init(
        nodes: [SwiftGraphNode],
        edges: [SwiftGraphEdge],
        couplingRisks: [CouplingRiskEvidence],
        dependencyContexts: [DependencyContext],
        statistics: CallGraphStatistics,
        dot: String
    ) {
        self.nodes = nodes
        self.edges = edges
        self.couplingRisks = couplingRisks
        self.dependencyContexts = dependencyContexts
        self.statistics = statistics
        self.dot = dot
    }
}

package struct CallSiteFact: Hashable, Sendable {
    package let name: String
    package let labels: String
    package let location: SourceLocation

    package init(name: String, labels: String, location: SourceLocation) {
        self.name = name
        self.labels = labels
        self.location = location
    }
}
