import SCMACore

struct DebtReportGraphProjection {
    func make(from graph: SwiftDependencyGraph) -> DebtReportDependencyGraph {
        let nodes = graph.nodes.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id < rhs.id }
            if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.displayName < rhs.displayName
        }
        let edges = graph.edges.map { edge in
            SwiftGraphEdge(
                source: edge.source,
                target: edge.target,
                targetCandidates: edge.targetCandidates.sorted(),
                kind: edge.kind,
                unresolvedName: edge.unresolvedName,
                confidence: edge.confidence,
                location: edge.location,
                isTestCaller: edge.isTestCaller,
                note: edge.note
            )
        }.sorted(by: edgeOrder)
        return DebtReportDependencyGraph(
            nodes: nodes,
            edges: edges,
            statistics: graph.statistics
        )
    }

    private func edgeOrder(_ lhs: SwiftGraphEdge, _ rhs: SwiftGraphEdge) -> Bool {
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        if (lhs.target ?? "") != (rhs.target ?? "") { return (lhs.target ?? "") < (rhs.target ?? "") }
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.confidence.rawValue != rhs.confidence.rawValue {
            return lhs.confidence.rawValue < rhs.confidence.rawValue
        }
        if (lhs.unresolvedName ?? "") != (rhs.unresolvedName ?? "") {
            return (lhs.unresolvedName ?? "") < (rhs.unresolvedName ?? "")
        }
        if lhs.location.file != rhs.location.file { return lhs.location.file < rhs.location.file }
        if lhs.location.line != rhs.location.line { return lhs.location.line < rhs.location.line }
        if lhs.location.column != rhs.location.column { return lhs.location.column < rhs.location.column }
        if lhs.targetCandidates != rhs.targetCandidates {
            return lhs.targetCandidates.lexicographicallyPrecedes(rhs.targetCandidates)
        }
        if lhs.isTestCaller != rhs.isTestCaller { return !lhs.isTestCaller }
        return lhs.note < rhs.note
    }
}
