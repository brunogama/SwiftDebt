package struct DependencyGraphBuilder: Sendable {
    package init() {}

    fileprivate struct GraphTypeInfo: Sendable {
        let key: TypeKey
        let kind: String
        let location: SourceLocation
        let fragments: [TypeFragment]
        let isTest: Bool
    }

    fileprivate struct FunctionInfo: Sendable {
        let fact: FunctionFacts
        let module: String
        let isTest: Bool
        let nodeID: String
    }

    private enum Resolution<T> {
        case resolved(T)
        case ambiguous([T])
        case unresolved
    }

    package func build(from sources: [ParsedSource], typeScope: TypeScope) -> SwiftDependencyGraph {
        let validSources = sources.filter(\.isValid).sorted { $0.path < $1.path }
        let typeInfos = aggregateTypes(validSources, scope: typeScope)
        let typeByKey = Dictionary(uniqueKeysWithValues: typeInfos.map { ($0.key, $0) })
        let functions = validSources.flatMap { source in
            source.functions.map { function in
                FunctionInfo(
                    fact: function,
                    module: source.module,
                    isTest: isTestSource(path: source.path, module: source.module),
                    nodeID: callableNodeID(function)
                )
            }
        }.sorted(by: functionOrder)
        let functionNames = Dictionary(grouping: functions, by: { $0.fact.name })
        var nodes = moduleNodes(validSources)
        nodes += typeInfos.map { type in
            SwiftGraphNode(
                id: typeNodeID(type.key), kind: .type, module: type.key.module,
                displayName: type.key.displayName, location: type.location, isTest: type.isTest
            )
        }
        nodes += functions.map { function in
            SwiftGraphNode(
                id: function.nodeID, kind: .callable, module: function.module,
                displayName: function.fact.name, location: function.fact.location, isTest: function.isTest
            )
        }
        nodes.sort(by: nodeOrder)
        var edges: [SwiftGraphEdge] = []
        edges += moduleEdges(typeInfos: typeInfos, typeByKey: typeByKey)
        edges += typeReferenceEdges(typeInfos: typeInfos, typeByKey: typeByKey)
        edges += callEdges(functions: functions, functionNames: functionNames)
        edges.sort(by: edgeOrder)
        let risks = couplingRisks(nodes: nodes, edges: edges)
        let contexts = dependencyContexts(for: risks, nodes: nodes, edges: edges)
        let statistics = statistics(nodes: nodes, edges: edges)
        return SwiftDependencyGraph(
            nodes: nodes, edges: edges, couplingRisks: risks,
            dependencyContexts: contexts, statistics: statistics,
            dot: dot(nodes: nodes, edges: edges)
        )
    }

    private func aggregateTypes(_ sources: [ParsedSource], scope: TypeScope) -> [GraphTypeInfo] {
        let sourceByPath = Dictionary(uniqueKeysWithValues: sources.map { ($0.path, $0) })
        let fragments = sources.flatMap(\.types)
        var result: [GraphTypeInfo] = []
        for (key, group) in Dictionary(grouping: fragments, by: \.key) {
            let bases = group.filter { !$0.isExtension }.sorted { locationOrder($0.location, $1.location) }
            guard let base = bases.first, bases.count == 1 else { continue }
            guard scope == .nominals || base.kind == "class" else { continue }
            let isTest = group.contains { fragment in
                sourceByPath[fragment.location.file].map { isTestSource(path: $0.path, module: $0.module) } ?? false
            }
            result.append(
                GraphTypeInfo(
                    key: key, kind: base.kind, location: base.location,
                    fragments: group.sorted { locationOrder($0.location, $1.location) }, isTest: isTest
                )
            )
        }
        return result.sorted { $0.key.displayName < $1.key.displayName }
    }

    private func moduleNodes(_ sources: [ParsedSource]) -> [SwiftGraphNode] {
        Set(sources.map(\.module)).sorted().map { module in
            SwiftGraphNode(
                id: moduleNodeID(module), kind: .module, module: module,
                displayName: module, isTest: isTestSource(path: "", module: module)
            )
        }
    }

    private func moduleEdges(
        typeInfos: [GraphTypeInfo], typeByKey: [TypeKey: GraphTypeInfo]
    ) -> [SwiftGraphEdge] {
        var edges: Set<SwiftGraphEdge> = []
        for type in typeInfos {
            for fragment in type.fragments {
                if case .resolved(let other) = resolveType(
                    fragment.key.name, from: type.key, imports: fragment.importedModules, types: typeByKey
                ), other.module != type.key.module {
                    edges.insert(moduleEdge(source: type.key.module, target: other.module, location: fragment.location))
                }
                for name in fragment.referencedTypes {
                    if case .resolved(let other) = resolveType(
                        name, from: type.key, imports: fragment.importedModules, types: typeByKey
                    ), other.module != type.key.module {
                        edges.insert(moduleEdge(source: type.key.module, target: other.module, location: fragment.location))
                    }
                }
            }
        }
        return Array(edges)
    }

    private func moduleEdge(source: String, target: String, location: SourceLocation) -> SwiftGraphEdge {
        SwiftGraphEdge(
            source: moduleNodeID(source), target: moduleNodeID(target), kind: .moduleDependency,
            confidence: .resolvedSyntax, location: location,
            note: "SwiftSyntax-only module dependency inferred from resolved in-input syntax; not compiler semantic proof."
        )
    }

    private func typeReferenceEdges(
        typeInfos: [GraphTypeInfo], typeByKey: [TypeKey: GraphTypeInfo]
    ) -> [SwiftGraphEdge] {
        var result: [SwiftGraphEdge] = []
        for type in typeInfos {
            for fragment in type.fragments {
                for name in fragment.referencedTypes.sorted() {
                    let source = typeNodeID(type.key)
                    switch resolveType(name, from: type.key, imports: fragment.importedModules, types: typeByKey) {
                    case .resolved(let target):
                        guard target != type.key else { continue }
                        result.append(
                            SwiftGraphEdge(
                                source: source, target: typeNodeID(target), kind: .typeReference,
                                unresolvedName: nil, confidence: .resolvedSyntax, location: fragment.location,
                                isTestCaller: type.isTest,
                                note: "SwiftSyntax-only type reference matched to one in-input declaration; not compiler semantic proof."
                            )
                        )
                    case .ambiguous(let candidates):
                        result.append(
                            SwiftGraphEdge(
                                source: source, target: nil, targetCandidates: candidates.map(typeNodeID).sorted(),
                                kind: .typeReference, unresolvedName: name, confidence: .ambiguousSyntax,
                                location: fragment.location, isTestCaller: type.isTest,
                                note: "SwiftSyntax-only type reference matched multiple in-input declarations; no compiler binding is claimed."
                            )
                        )
                    case .unresolved:
                        result.append(
                            SwiftGraphEdge(
                                source: source, target: nil, kind: .typeReference, unresolvedName: name,
                                confidence: .unresolvedSyntax, location: fragment.location, isTestCaller: type.isTest,
                                note: "SwiftSyntax-only type reference was not resolved inside selected inputs; no compiler binding is claimed."
                            )
                        )
                    }
                }
            }
        }
        return result
    }

    private func callEdges(
        functions: [FunctionInfo], functionNames: [String: [FunctionInfo]]
    ) -> [SwiftGraphEdge] {
        var result: [SwiftGraphEdge] = []
        for function in functions {
            for call in function.fact.callSites.sorted(by: callSiteOrder) {
                let display = callDisplayName(call)
                switch resolveCall(call, from: function, functionNames: functionNames) {
                case .resolved(let target):
                    result.append(
                        SwiftGraphEdge(
                            source: function.nodeID, target: target.nodeID, kind: .call,
                            unresolvedName: nil, confidence: .resolvedSyntax, location: call.location,
                            isTestCaller: function.isTest,
                            note: "SwiftSyntax-only call matched to one in-input callable by name and argument labels; not compiler semantic proof."
                        )
                    )
                case .ambiguous(let candidates):
                    result.append(
                        SwiftGraphEdge(
                            source: function.nodeID, target: nil,
                            targetCandidates: candidates.map(\.nodeID).sorted(), kind: .call,
                            unresolvedName: display, confidence: .ambiguousSyntax, location: call.location,
                            isTestCaller: function.isTest,
                            note: "SwiftSyntax-only call matched multiple in-input callables; overload binding requires the compiler; no compiler binding is claimed."
                        )
                    )
                case .unresolved:
                    result.append(
                        SwiftGraphEdge(
                            source: function.nodeID, target: nil, kind: .call,
                            unresolvedName: display, confidence: .unresolvedSyntax, location: call.location,
                            isTestCaller: function.isTest,
                            note: "SwiftSyntax-only call was not resolved inside selected inputs; no compiler binding is claimed."
                        )
                    )
                }
            }
        }
        return result
    }

    private func resolveType(
        _ name: String, from source: TypeKey, imports: Set<String>, types: [TypeKey: GraphTypeInfo]
    ) -> Resolution<TypeKey> {
        var parents = source.name.split(separator: ".").map(String.init)
        while !parents.isEmpty {
            let candidate = TypeKey(module: source.module, name: (parents + [name]).joined(separator: "."))
            if types[candidate] != nil { return .resolved(candidate) }
            parents.removeLast()
        }
        let sameModule = TypeKey(module: source.module, name: name)
        if types[sameModule] != nil { return .resolved(sameModule) }
        let parts = name.split(separator: ".").map(String.init)
        if parts.count > 1 {
            let qualified = TypeKey(module: parts[0], name: parts.dropFirst().joined(separator: "."))
            if types[qualified] != nil { return .resolved(qualified) }
            let nestedSameModule = TypeKey(module: source.module, name: name)
            if types[nestedSameModule] != nil { return .resolved(nestedSameModule) }
        }
        let imported = imports.map { TypeKey(module: $0, name: name) }.filter { types[$0] != nil }.sorted {
            $0.displayName < $1.displayName
        }
        if imported.count == 1 { return .resolved(imported[0]) }
        if imported.count > 1 { return .ambiguous(imported) }
        let sameName = types.keys.filter { $0.name == name }.sorted { $0.displayName < $1.displayName }
        return sameName.count > 1 ? .ambiguous(sameName) : .unresolved
    }

    private func resolveCall(
        _ call: CallSiteFact, from source: FunctionInfo, functionNames: [String: [FunctionInfo]]
    ) -> Resolution<FunctionInfo> {
        let base = call.name.split(separator: ".").last.map(String.init) ?? call.name
        let display = "\(base)(\(call.labels))"
        var candidateNames: [String] = []
        if call.name.hasPrefix("self."), let owner = source.fact.owner {
            candidateNames.append("\(owner.displayName).\(display)")
        } else if call.name.hasPrefix("Self."), let owner = source.fact.owner {
            candidateNames.append("\(owner.displayName).\(display)")
        } else if call.name.contains("."), let owner = source.fact.owner {
            candidateNames.append("\(owner.module).\(call.name)(\(call.labels))")
        } else {
            if let owner = source.fact.owner { candidateNames.append("\(owner.displayName).\(display)") }
            candidateNames.append("\(source.module).\(display)")
        }
        let candidates = candidateNames.flatMap { functionNames[$0, default: []] }
            .filter { $0.nodeID != source.nodeID }
            .sorted(by: functionOrder)
        if candidates.count == 1 { return .resolved(candidates[0]) }
        if candidates.count > 1 { return .ambiguous(candidates) }
        return .unresolved
    }

    private func couplingRisks(nodes: [SwiftGraphNode], edges: [SwiftGraphEdge]) -> [CouplingRiskEvidence] {
        let resolved = edges.filter { $0.confidence == .resolvedSyntax }
        return nodes.filter { $0.kind != .module }.map { node in
            let outgoing = resolved.filter { $0.source == node.id && $0.target != nil }.map { $0.target! }
            let incoming = resolved.filter { $0.target == node.id }.map(\.source)
            let callerEdges = resolved.filter { $0.kind == .call && $0.target == node.id }
            let callerIDs = Set(callerEdges.map(\.source))
            let productionCallers = Set(callerEdges.filter { !$0.isTestCaller }.map(\.source))
            let testCallers = Set(callerEdges.filter(\.isTestCaller).map(\.source))
            let denominator = incoming.count + outgoing.count
            let instability = denominator == 0 ? nil : Double(outgoing.count) / Double(denominator)
            return CouplingRiskEvidence(
                entityID: node.id, entityDisplayName: node.displayName, entityKind: node.kind,
                afferentCoupling: incoming.count, efferentCoupling: outgoing.count,
                callerCount: callerIDs.count, productionCallerCount: productionCallers.count,
                testCallerCount: testCallers.count, fanIn: Set(incoming).count,
                fanOut: Set(outgoing).count, instability: instability,
                note: "Deterministic SwiftSyntax graph counts; unresolved and ambiguous edges are excluded rather than treated as compiler facts."
            )
        }.sorted { $0.entityID < $1.entityID }
    }

    private func dependencyContexts(
        for risks: [CouplingRiskEvidence], nodes: [SwiftGraphNode], edges: [SwiftGraphEdge]
    ) -> [DependencyContext] {
        let nodeByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let resolved = edges.filter { $0.confidence == .resolvedSyntax }
        return risks.map { risk in
            let node = nodeByID[risk.entityID]
            let upstream = Set(resolved.filter { $0.source == risk.entityID }.compactMap(\.target)).sorted()
            let downstream = Set(resolved.filter { $0.target == risk.entityID }.map(\.source)).sorted()
            let instability = risk.instability.map { String($0) } ?? "n/a"
            let rawParts: [String] = [
                "afferent=\(risk.afferentCoupling)",
                "efferent=\(risk.efferentCoupling)",
                "callers=\(risk.callerCount)",
                "productionCallers=\(risk.productionCallerCount)",
                "testCallers=\(risk.testCallerCount)",
                "fanIn=\(risk.fanIn)",
                "fanOut=\(risk.fanOut)",
                "instability=\(instability)",
            ]
            let raw = rawParts.joined(separator: ";")
            let entity = DebtEntity(
                id: risk.entityID, displayName: risk.entityDisplayName,
                level: risk.entityKind == .callable ? .callable : .type,
                location: DebtLocation(module: node?.module, source: node?.location ?? SourceLocation(file: "", line: 1))
            )
            return DependencyContext(
                entity: entity, upstreamDependencies: upstream, downstreamDependents: downstream,
                evidence: [
                    DebtEvidence(
                        id: "\(risk.entityID):dependency-context",
                        kind: "swift.dependency-context",
                        weight: 1,
                        normalizedScore: Double(min(100, risk.fanIn * 10 + risk.fanOut * 10 + risk.callerCount * 5)),
                        rawValue: raw,
                        location: entity.location,
                        note: "Critical-path dependency context from deterministic SwiftSyntax edges; not compiler semantic proof."
                    )
                ]
            )
        }.sorted { $0.entity.id < $1.entity.id }
    }

    private func statistics(nodes: [SwiftGraphNode], edges: [SwiftGraphEdge]) -> CallGraphStatistics {
        CallGraphStatistics(
            nodeCount: nodes.count,
            edgeCount: edges.count,
            resolvedEdgeCount: edges.filter { $0.confidence == .resolvedSyntax }.count,
            ambiguousEdgeCount: edges.filter { $0.confidence == .ambiguousSyntax }.count,
            unresolvedEdgeCount: edges.filter { $0.confidence == .unresolvedSyntax }.count,
            syntaxOnlyNote: "SwiftSyntax-only graph evidence; unresolved and ambiguous edges are explicit and not compiler semantic proof."
        )
    }

    private func dot(nodes: [SwiftGraphNode], edges: [SwiftGraphEdge]) -> String {
        var lines = ["digraph SwiftDependencyGraph {", "  rankdir=LR;"]
        for node in nodes {
            lines.append("  \"\(escapeDOT(node.id))\" [label=\"\(escapeDOT(node.displayName))\", kind=\"\(node.kind.rawValue)\"];")
        }
        for edge in edges {
            let target = edge.target ?? "unresolved:\(edge.kind.rawValue):\(edge.unresolvedName ?? "unknown")"
            lines.append(
                "  \"\(escapeDOT(edge.source))\" -> \"\(escapeDOT(target))\" [label=\"\(edge.kind.rawValue):\(edge.confidence.rawValue)\"];"
            )
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private func moduleNodeID(_ module: String) -> String { "module:\(module)" }
    private func typeNodeID(_ key: TypeKey) -> String { "type:\(key.displayName)" }
    private func callableNodeID(_ function: FunctionFacts) -> String {
        "callable:\(function.name)@\(function.location.file):\(function.location.line):\(function.location.column)"
    }
    private func callDisplayName(_ call: CallSiteFact) -> String {
        let base = call.name.split(separator: ".").last.map(String.init) ?? call.name
        return "\(base)(\(call.labels))"
    }
    private func isTestSource(path: String, module: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return module.hasSuffix("Tests") || module.hasSuffix("Test") || components.contains("Tests")
            || components.contains { $0.hasSuffix("Tests") } || path.hasSuffix("Tests.swift")
    }
    private func escapeDOT(_ value: String) -> String {
        var result = ""
        for character in value {
            if character == "\\" { result += "\\\\" }
            else if character == "\"" { result += "\\\"" }
            else { result.append(character) }
        }
        return result
    }
}

private func nodeOrder(_ lhs: SwiftGraphNode, _ rhs: SwiftGraphNode) -> Bool {
    if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    return lhs.displayName < rhs.displayName
}

private func edgeOrder(_ lhs: SwiftGraphEdge, _ rhs: SwiftGraphEdge) -> Bool {
    if lhs.source != rhs.source { return lhs.source < rhs.source }
    if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
    if (lhs.target ?? "") != (rhs.target ?? "") { return (lhs.target ?? "") < (rhs.target ?? "") }
    if (lhs.unresolvedName ?? "") != (rhs.unresolvedName ?? "") {
        return (lhs.unresolvedName ?? "") < (rhs.unresolvedName ?? "")
    }
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    return lhs.confidence.rawValue < rhs.confidence.rawValue
}

private func functionOrder(_ lhs: DependencyGraphBuilder.FunctionInfo, _ rhs: DependencyGraphBuilder.FunctionInfo) -> Bool {
    if lhs.fact.name != rhs.fact.name { return lhs.fact.name < rhs.fact.name }
    if lhs.fact.location != rhs.fact.location { return locationOrder(lhs.fact.location, rhs.fact.location) }
    return lhs.nodeID < rhs.nodeID
}

private func callSiteOrder(_ lhs: CallSiteFact, _ rhs: CallSiteFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    return lhs.labels < rhs.labels
}
