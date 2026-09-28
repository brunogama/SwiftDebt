extension DependencyGraphBuilder {
    package func couplingRisks(nodes: [SwiftGraphNode], edges: [SwiftGraphEdge])
        -> [CouplingRiskEvidence]
    {
        let resolved = edges.filter { $0.confidence == .resolvedSyntax }
        return nodes.filter { $0.kind != .module }.map { node in
            let outgoing = resolved.filter { $0.source == node.id && $0.target != nil }.map {
                $0.target!
            }
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
                note:
                    "Deterministic SwiftSyntax graph counts; unresolved and ambiguous edges are "
                    + "excluded rather than treated as compiler facts."
            )
        }.sorted { $0.entityID < $1.entityID }
    }

    package func dependencyContexts(
        for risks: [CouplingRiskEvidence], entities: [DebtEntity], edges: [SwiftGraphEdge]
    ) -> [DependencyContext] {
        let resolved = edges.filter { $0.confidence == .resolvedSyntax }
        return zip(risks, entities).map { risk, entity in
            let upstream = Set(resolved.filter { $0.source == risk.entityID }.compactMap(\.target))
                .sorted()
            let downstream = Set(resolved.filter { $0.target == risk.entityID }.map(\.source))
                .sorted()
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
            return DependencyContext(
                entity: entity, upstreamDependencies: upstream, downstreamDependents: downstream,
                evidence: [
                    DebtEvidence(
                        id: "\(risk.entityID):dependency-context",
                        kind: "swift.dependency-context",
                        weight: 1,
                        normalizedScore: Double(
                            min(100, risk.fanIn * 10 + risk.fanOut * 10 + risk.callerCount * 5)),
                        rawValue: raw,
                        location: entity.location,
                        note:
                            "One-hop dependency context from deterministic SwiftSyntax edges; "
                            + "not "
                            + "compiler semantic proof."
                    )
                ]
            )
        }.sorted { $0.entity.id < $1.entity.id }
    }

    package func statistics(nodes: [SwiftGraphNode], edges: [SwiftGraphEdge]) -> CallGraphStatistics
    {
        CallGraphStatistics(
            nodeCount: nodes.count,
            edgeCount: edges.count,
            resolvedEdgeCount: edges.filter { $0.confidence == .resolvedSyntax }.count,
            ambiguousEdgeCount: edges.filter { $0.confidence == .ambiguousSyntax }.count,
            unresolvedEdgeCount: edges.filter { $0.confidence == .unresolvedSyntax }.count,
            syntaxOnlyNote:
                "SwiftSyntax-only graph evidence; unresolved and ambiguous edges are explicit "
                + "and not compiler semantic proof."
        )
    }

    package func dot(nodes: [SwiftGraphNode], edges: [SwiftGraphEdge]) -> String {
        var lines = ["digraph SwiftDependencyGraph {", "  rankdir=LR;"]
        for node in nodes {
            lines.append(
                "  "
                    + "\"\(escapeDOT(node.id))\" [label=\"\(escapeDOT(node.displayName))\", kind=\"\(node.kind.rawValue)\"];"
            )
        }
        for edge in edges {
            let unresolvedTarget = ["unresolved", edge.kind.rawValue, edge.unresolvedName]
                .compactMap { $0 }
                .joined(separator: ":")
            let target = edge.target ?? unresolvedTarget
            lines.append(
                "  "
                    + "\"\(escapeDOT(edge.source))\" -> \"\(escapeDOT(target))\" [label=\"\(edge.kind.rawValue):\(edge.confidence.rawValue)\"];"
            )
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }
}
