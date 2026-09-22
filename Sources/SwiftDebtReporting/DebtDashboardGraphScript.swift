extension DebtDashboardApplication {
    static var graphFunction: String {
        """
          function renderGraph() {
            const box = q("graph");
            box.replaceChildren();
            const graph = report.dependencyGraph;
            if (!graph || !Array.isArray(graph.nodes) || !Array.isArray(graph.edges)) {
              box.append(el("p", "No dependency or call graph is present in this report.", "empty"));
              return;
            }
            const statistics = graph.statistics || {};
            box.append(el(
              "p",
              `${score(statistics.nodeCount)} nodes; ${score(statistics.edgeCount)} edges; ${score(statistics.resolvedEdgeCount)} resolved; ${score(statistics.ambiguousEdgeCount)} ambiguous; ${score(statistics.unresolvedEdgeCount)} unresolved.`
            ));
            if (statistics.syntaxOnlyNote) box.append(el("p", statistics.syntaxOnlyNote, "meta"));
            if (!graph.edges.length) {
              box.append(el("p", "The dependency graph has no edges.", "empty"));
              return;
            }
            const nodes = new Map(graph.nodes.map(node => [node.id, node]));
            const list = el("ul");
            list.ariaLabel = "Dependency and call graph edges";
            graph.edges.forEach(edge => {
              const source = nodes.get(edge.source)?.displayName || edge.source;
              const resolvedTarget = edge.target && nodes.get(edge.target);
              let target = resolvedTarget?.displayName || edge.target || edge.unresolvedName || "unresolved";
              if (!edge.target && edge.targetCandidates && edge.targetCandidates.length) {
                const candidates = edge.targetCandidates.map(id => nodes.get(id)?.displayName || id);
                target += ` [candidates: ${candidates.join(", ")}]`;
              }
              const value = `${source} -> ${target} (${edge.kind}, ${edge.confidence}) at ${location(edge.location)}`;
              list.append(el("li", value, "edge"));
            });
            box.append(list);
          }
        """
    }
}
