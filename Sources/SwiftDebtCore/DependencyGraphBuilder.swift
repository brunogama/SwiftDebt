package struct DependencyGraphBuilder: Sendable {
    package init() {}

    package struct GraphTypeInfo: Sendable {
        let key: TypeKey
        let kind: String
        let location: SourceLocation
        let fragments: [TypeFragment]
        let isTest: Bool
    }

    package struct FunctionInfo: Sendable {
        let fact: FunctionFacts
        let module: String
        let isTest: Bool
        let nodeID: String
    }

    package enum Resolution<T> {
        case resolved(T)
        case ambiguous([T])
        case unresolved
    }

    package func build(from sources: [ParsedSource], typeScope: TypeScope) -> SwiftDependencyGraph {
        let validSources = sources.filter(\.isValid).sorted { $0.path < $1.path }
        let typeInfos = aggregateTypes(validSources, scope: typeScope)
        let typeByKey = Dictionary(uniqueKeysWithValues: typeInfos.map { ($0.key, $0) })
        let functions = functionInfos(validSources)
        let functionNames = Dictionary(grouping: functions, by: { $0.fact.name })
        let nodes = graphNodes(sources: validSources, types: typeInfos, functions: functions)
        let edges = graphEdges(
            types: typeInfos, typeByKey: typeByKey, functions: functions,
            functionNames: functionNames)
        let risks = couplingRisks(nodes: nodes, edges: edges)
        let contextEntities = contextEntities(types: typeInfos, functions: functions)
        let contexts = dependencyContexts(for: risks, entities: contextEntities, edges: edges)
        let statistics = statistics(nodes: nodes, edges: edges)
        return SwiftDependencyGraph(
            nodes: nodes, edges: edges, couplingRisks: risks,
            dependencyContexts: contexts, statistics: statistics,
            dot: dot(nodes: nodes, edges: edges)
        )
    }

    private func functionInfos(_ sources: [ParsedSource]) -> [FunctionInfo] {
        sources.flatMap { source in
            source.functions.map { function in
                FunctionInfo(
                    fact: function, module: source.module,
                    isTest: isTestSource(path: source.path, module: source.module),
                    nodeID: callableNodeID(function))
            }
        }.sorted(by: functionOrder)
    }

    private func graphNodes(
        sources: [ParsedSource], types: [GraphTypeInfo], functions: [FunctionInfo]
    ) -> [SwiftGraphNode] {
        var nodes = moduleNodes(sources)
        nodes += types.map {
            SwiftGraphNode(
                id: typeNodeID($0.key), kind: .type, module: $0.key.module,
                displayName: $0.key.displayName, location: $0.location, isTest: $0.isTest)
        }
        nodes += functions.map {
            SwiftGraphNode(
                id: $0.nodeID, kind: .callable, module: $0.module,
                displayName: $0.fact.name, location: $0.fact.location, isTest: $0.isTest)
        }
        return nodes.sorted(by: nodeOrder)
    }

    private func graphEdges(
        types: [GraphTypeInfo], typeByKey: [TypeKey: GraphTypeInfo],
        functions: [FunctionInfo], functionNames: [String: [FunctionInfo]]
    ) -> [SwiftGraphEdge] {
        var edges = moduleEdges(typeInfos: types, typeByKey: typeByKey)
        edges += typeReferenceEdges(typeInfos: types, typeByKey: typeByKey)
        edges += callEdges(functions: functions, functionNames: functionNames)
        return edges.sorted(by: edgeOrder)
    }

    private func contextEntities(
        types: [GraphTypeInfo], functions: [FunctionInfo]
    ) -> [DebtEntity] {
        let typeEntities = types.map {
            DebtEntity(
                id: typeNodeID($0.key), displayName: $0.key.displayName, level: .type,
                location: DebtLocation(module: $0.key.module, source: $0.location))
        }
        let functionEntities = functions.map {
            DebtEntity(
                id: $0.nodeID, displayName: $0.fact.name, level: .callable,
                location: DebtLocation(module: $0.module, source: $0.fact.location))
        }
        return (typeEntities + functionEntities).sorted { $0.id < $1.id }
    }

}

private func nodeOrder(_ lhs: SwiftGraphNode, _ rhs: SwiftGraphNode) -> Bool {
    (lhs.kind.rawValue, lhs.id) < (rhs.kind.rawValue, rhs.id)
}

private func edgeOrder(_ lhs: SwiftGraphEdge, _ rhs: SwiftGraphEdge) -> Bool {
    let lhsTarget = lhs.target ?? ""
    let rhsTarget = rhs.target ?? ""
    let lhsUnresolvedName = lhs.unresolvedName ?? ""
    let rhsUnresolvedName = rhs.unresolvedName ?? ""
    if lhs.source != rhs.source { return lhs.source < rhs.source }
    if lhsTarget != rhsTarget { return lhsTarget < rhsTarget }
    if lhsUnresolvedName != rhsUnresolvedName {
        return lhsUnresolvedName < rhsUnresolvedName
    }
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    return lhs.confidence.rawValue < rhs.confidence.rawValue
}

private func functionOrder(
    _ lhs: DependencyGraphBuilder.FunctionInfo, _ rhs: DependencyGraphBuilder.FunctionInfo
)
    -> Bool
{
    (
        lhs.fact.name, lhs.fact.location.file, lhs.fact.location.line, lhs.fact.location.column
    ) < (
        rhs.fact.name, rhs.fact.location.file, rhs.fact.location.line, rhs.fact.location.column
    )
}

private func callSiteOrder(_ lhs: CallSiteFact, _ rhs: CallSiteFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    return lhs.labels < rhs.labels
}
