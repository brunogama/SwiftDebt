extension DependencyGraphBuilder {
    package func aggregateTypes(_ sources: [ParsedSource], scope: TypeScope) -> [GraphTypeInfo] {
        let sourcesByPath = Dictionary(grouping: sources, by: \.path)
        let fragments = sources.flatMap(\.types)
        var result: [GraphTypeInfo] = []
        for (key, group) in Dictionary(grouping: fragments, by: \.key) {
            let bases = group.filter { !$0.isExtension }.sorted {
                locationOrder($0.location, $1.location)
            }
            guard let base = bases.first, bases.count == 1 else { continue }
            guard scope == .nominals || base.kind == "class" else { continue }
            let isTest = group.contains { fragment in
                sourcesByPath[fragment.location.file]?.contains { source in
                    source.module == key.module
                        && isTestSource(path: source.path, module: source.module)
                } ?? false
            }
            result.append(
                GraphTypeInfo(
                    key: key, kind: base.kind, location: base.location,
                    fragments: group.sorted { locationOrder($0.location, $1.location) },
                    isTest: isTest
                )
            )
        }
        return result.sorted { $0.key.displayName < $1.key.displayName }
    }

    package func moduleNodes(_ sources: [ParsedSource]) -> [SwiftGraphNode] {
        Set(sources.map(\.module)).sorted().map { module in
            SwiftGraphNode(
                id: moduleNodeID(module), kind: .module, module: module,
                displayName: module, isTest: isTestSource(path: "", module: module)
            )
        }
    }

    package func moduleEdges(
        typeInfos: [GraphTypeInfo], typeByKey: [TypeKey: GraphTypeInfo]
    ) -> [SwiftGraphEdge] {
        var edges: Set<SwiftGraphEdge> = []
        for type in typeInfos {
            for fragment in type.fragments {
                for name in fragment.referencedTypes {
                    if case .resolved(let other) = resolveType(
                        name, from: type.key, imports: fragment.importedModules, types: typeByKey
                    ), other.module != type.key.module {
                        edges.insert(
                            moduleEdge(
                                source: type.key.module, target: other.module,
                                location: fragment.location))
                    }
                }
            }
        }
        return Array(edges)
    }

    package func moduleEdge(source: String, target: String, location: SourceLocation)
        -> SwiftGraphEdge
    {
        SwiftGraphEdge(
            source: moduleNodeID(source), target: moduleNodeID(target), kind: .moduleDependency,
            confidence: .resolvedSyntax, location: location,
            note:
                "SwiftSyntax-only module dependency inferred from resolved in-input syntax; not "
                + "compiler semantic proof."
        )
    }

    package func typeReferenceEdges(
        typeInfos: [GraphTypeInfo], typeByKey: [TypeKey: GraphTypeInfo]
    ) -> [SwiftGraphEdge] {
        var result: [SwiftGraphEdge] = []
        for type in typeInfos {
            for fragment in type.fragments {
                for name in fragment.referencedTypes.sorted() {
                    if let edge = typeReferenceEdge(
                        name: name, type: type, fragment: fragment, types: typeByKey)
                    {
                        result.append(edge)
                    }
                }
            }
        }
        return result
    }

    private func typeReferenceEdge(
        name: String, type: GraphTypeInfo, fragment: TypeFragment,
        types: [TypeKey: GraphTypeInfo]
    ) -> SwiftGraphEdge? {
        let source = typeNodeID(type.key)
        switch resolveType(
            name, from: type.key, imports: fragment.importedModules, types: types)
        {
        case .resolved(let target):
            guard target != type.key else { return nil }
            return SwiftGraphEdge(
                source: source, target: typeNodeID(target), kind: .typeReference,
                unresolvedName: nil, confidence: .resolvedSyntax, location: fragment.location,
                isTestCaller: type.isTest,
                note: "SwiftSyntax-only type reference matched to one in-input declaration; "
                    + "not compiler semantic proof.")
        case .ambiguous(let candidates):
            return SwiftGraphEdge(
                source: source, target: nil, targetCandidates: candidates.map(typeNodeID).sorted(),
                kind: .typeReference, unresolvedName: name, confidence: .ambiguousSyntax,
                location: fragment.location, isTestCaller: type.isTest,
                note: "SwiftSyntax-only type reference matched multiple in-input declarations; "
                    + "no compiler binding is claimed.")
        case .unresolved:
            return SwiftGraphEdge(
                source: source, target: nil, kind: .typeReference, unresolvedName: name,
                confidence: .unresolvedSyntax, location: fragment.location,
                isTestCaller: type.isTest,
                note: "SwiftSyntax-only type reference was not resolved inside selected inputs; "
                    + "no compiler binding is claimed.")
        }
    }

    package func callEdges(
        functions: [FunctionInfo], functionNames: [String: [FunctionInfo]]
    ) -> [SwiftGraphEdge] {
        var result: [SwiftGraphEdge] = []
        for function in functions {
            for call in function.fact.callSites.sorted(by: dependencyCallSiteOrder) {
                result.append(callEdge(call, from: function, functionNames: functionNames))
            }
        }
        return result
    }

    private func callEdge(
        _ call: CallSiteFact, from function: FunctionInfo,
        functionNames: [String: [FunctionInfo]]
    ) -> SwiftGraphEdge {
        let display = callDisplayName(call)
        switch resolveCall(call, from: function, functionNames: functionNames) {
        case .resolved(let target):
            return SwiftGraphEdge(
                source: function.nodeID, target: target.nodeID, kind: .call,
                unresolvedName: nil, confidence: .resolvedSyntax, location: call.location,
                isTestCaller: function.isTest,
                note: "SwiftSyntax-only call matched to one in-input callable by name and "
                    + "argument labels; not compiler semantic proof.")
        case .ambiguous(let candidates):
            return SwiftGraphEdge(
                source: function.nodeID, target: nil,
                targetCandidates: candidates.map(\.nodeID).sorted(), kind: .call,
                unresolvedName: display, confidence: .ambiguousSyntax, location: call.location,
                isTestCaller: function.isTest,
                note: "SwiftSyntax-only call matched multiple in-input callables; overload "
                    + "binding requires the compiler; no compiler binding is claimed.")
        case .unresolved:
            return SwiftGraphEdge(
                source: function.nodeID, target: nil, kind: .call, unresolvedName: display,
                confidence: .unresolvedSyntax, location: call.location,
                isTestCaller: function.isTest,
                note: "SwiftSyntax-only call was not resolved inside selected inputs; no "
                    + "compiler binding is claimed.")
        }
    }
}

private func dependencyCallSiteOrder(_ lhs: CallSiteFact, _ rhs: CallSiteFact) -> Bool {
    if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    return lhs.labels < rhs.labels
}
