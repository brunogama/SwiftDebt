extension DebtDashboardApplication {
    static var comparisonFunctions: String {
        """
          function snapshotState(item) {
            return `${score(item.score)} / ${item.priority || "unscored"} at ${location(item.location)}`;
          }

          function deltaState(change) {
            const parts = [signed(change.score && change.score.delta)];
            if (change.moved) parts.push("moved");
            const evidence = change.evidence || { added: [], removed: [] };
            if (evidence.added.length || evidence.removed.length) {
              parts.push(`evidence +${evidence.added.length}/-${evidence.removed.length}`);
            }
            return parts.join("; ");
          }

          function renderItemChanges(box) {
            const changes = comparison.itemChanges;
            const table = el("table");
            table.innerHTML = "<thead><tr><th>Change</th><th>Item</th><th>Before</th><th>After</th><th>Delta</th></tr></thead>";
            const body = el("tbody");
            changes.added.forEach(item => appendRow(
              body,
              ["added", item.displayName, "not present", snapshotState(item), "added"]
            ));
            changes.removed.forEach(item => appendRow(
              body,
              ["removed", item.displayName, snapshotState(item), "not present", "removed"]
            ));
            changes.changed.forEach(item => appendRow(body, [
              "changed",
              item.displayName,
              `${score(item.score.before)} / ${item.priority.before || "unscored"} at ${location(item.beforeLocation)}`,
              `${score(item.score.after)} / ${item.priority.after || "unscored"} at ${location(item.afterLocation)}`,
              deltaState(item),
            ]));
            table.append(body);
            box.append(el("h3", "Item changes"), table);
          }

          function renderAggregationChanges(box) {
            const changes = comparison.aggregationChanges;
            if (!changes.added.length && !changes.removed.length && !changes.changed.length) return;
            const table = el("table");
            table.innerHTML = "<thead><tr><th>Change</th><th>Aggregation</th><th>Before</th><th>After</th><th>Delta</th></tr></thead>";
            const body = el("tbody");
            changes.added.forEach(value => appendRow(
              body,
              ["added", value.displayName, "not present", snapshotState(value), "added"]
            ));
            changes.removed.forEach(value => appendRow(
              body,
              ["removed", value.displayName, snapshotState(value), "not present", "removed"]
            ));
            changes.changed.forEach(value => appendRow(body, [
              "changed",
              value.displayName,
              `${score(value.score.before)} / ${value.priority.before || "unscored"} at ${location(value.beforeLocation)}`,
              `${score(value.score.after)} / ${value.priority.after || "unscored"} at ${location(value.afterLocation)}`,
              `${signed(value.score.delta)}; members +${value.memberItemIDs.added.length}/-${value.memberItemIDs.removed.length}${value.moved ? "; moved" : ""}`,
            ]));
            table.append(body);
            box.append(el("h3", "Aggregation changes"), table);
          }

          function renderComparison() {
            const box = q("comparison");
            box.replaceChildren();
            if (!comparison) {
              box.append(el(
                "p",
                "Load a comparison report JSON to visualize priority, score, evidence, and aggregation changes.",
                "empty"
              ));
              return;
            }
            const summary = el("div", undefined, "cards");
            appendCard(summary, "Added items", comparison.summary.addedItemCount);
            appendCard(summary, "Removed items", comparison.summary.removedItemCount);
            appendCard(summary, "Changed items", comparison.summary.changedItemCount);
            appendCard(summary, "Total score delta", signed(comparison.summary.totalScoreDelta));
            appendCard(summary, "Unavailable evidence delta", signed(comparison.summary.unavailableEvidenceDelta));
            box.append(summary);
            renderItemChanges(box);
            renderAggregationChanges(box);
            box.append(el(
              "p",
              `Missing evidence IDs: +${comparison.missingEvidence.added.length}/-${comparison.missingEvidence.removed.length}`
            ));
          }
        """
    }
}
