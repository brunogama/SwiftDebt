extension DebtDashboardApplication {
    static var reportFunctions: String {
        """
          function priorities(value) {
            return ["critical", "high", "medium", "low", "unscored"].filter(priority =>
              priority === "unscored"
                ? value.items.some(item => !item.priority)
                : value.items.some(item => item.priority === priority)
            );
          }

          function categories(value) {
            return [...new Set(value.items.map(item => item.category).filter(Boolean))].sort();
          }

          function levels(value) {
            return [...new Set(value.items.map(item => item.level).filter(Boolean))].sort();
          }

          function fillSelect(id, values, label) {
            const select = q(id);
            const selected = select.value;
            select.replaceChildren(el("option", label));
            select.firstChild.value = "all";
            values.forEach(value => {
              const option = el("option", value);
              option.value = value;
              select.append(option);
            });
            select.value = ["all", ...values].includes(selected) ? selected : "all";
          }

          function filteredItems() {
            const needle = state.query.trim().toLowerCase();
            return report.items.filter(item =>
              (state.priority === "all"
                || (state.priority === "unscored" ? !item.priority : item.priority === state.priority))
              && (state.category === "all" || item.category === state.category)
              && (state.level === "all" || item.level === state.level)
              && (!needle || [
                item.id,
                item.displayName,
                item.category,
                item.level,
                location(item.location),
                ...(item.evidence || []).flatMap(evidence => [
                  evidence.id, evidence.kind, evidence.rawValue, evidence.note,
                ]),
              ].some(value => text(value).toLowerCase().includes(needle)))
            );
          }

          function appendCard(container, label, value, className) {
            const card = el("article", undefined, "card");
            card.append(el("strong", score(value), className), el("div", label));
            container.append(card);
          }

          function renderSummary() {
            const summary = report.summary || {};
            const box = q("summary");
            box.replaceChildren();
            [
              ["Ranked items", summary.rankedItemCount],
              ["Unavailable evidence", summary.unavailableEvidenceCount],
              ["Aggregations", summary.aggregationCount],
              ["Total items", summary.totalItemCount],
            ].forEach(([label, value]) => appendCard(box, label, value));
            Object.entries(summary.priorityCounts || {}).sort().forEach(([priority, count]) =>
              appendCard(box, `${priority} priority`, count, priority)
            );
          }

          function appendRow(body, values, rowHeaderClass) {
            const row = el("tr");
            values.forEach((value, index) => {
              const cell = el(index === 0 ? "th" : "td", value, index === 0 ? rowHeaderClass : undefined);
              if (index === 0) cell.scope = "row";
              row.append(cell);
            });
            body.append(row);
          }

          function renderTable(items) {
            const wrap = q("item-table");
            const table = el("table");
            table.innerHTML = "<thead><tr><th>Priority</th><th>Score</th><th>Entity</th><th>Level</th><th>Location</th><th>Category</th><th>Recommendation</th></tr></thead>";
            const body = el("tbody");
            items.forEach(item => {
              appendRow(body, [
                item.priority || "unscored",
                score(item.score),
                item.displayName,
                item.level,
                location(item.location),
                item.category,
                item.recommendation,
              ], item.priority || "");
              body.children[body.children.length - 1].id = item.id;
            });
            table.append(body);
            wrap.replaceChildren(table);
          }

          function renderDrilldown(items) {
            const box = q("drilldown");
            box.replaceChildren();
            if (!items.length) {
              box.append(el("p", "No items match the current filters.", "empty"));
              return;
            }
            items.forEach(item => {
              const details = el("details");
              const summary = el(
                "summary",
                `${item.displayName} - ${item.priority || "unscored"} - ${score(item.score)}`
              );
              const body = el("div");
              body.append(
                el("p", item.explanation),
                el("p", `Source: ${location(item.location)}`),
                el("p", `Action: ${item.recommendation}`)
              );
              const evidence = el("ul");
              (item.evidence || []).forEach(value => evidence.append(el(
                "li",
                `${value.kind}: ${value.rawValue} (${value.availability?.state || "unknown"}) ${value.availability?.reason || ""}`
              )));
              body.append(el("h3", "Evidence"), evidence);
              const breakdown = el("ul");
              ((item.scoreBreakdown && item.scoreBreakdown.contributions) || []).forEach(value =>
                breakdown.append(el(
                  "li",
                  `${value.kind}: ${score(value.normalizedScore)} weight ${score(value.effectiveWeight)} - ${value.rawValue}`
                ))
              );
              ((item.scoreBreakdown && item.scoreBreakdown.unavailableEvidence) || []).forEach(value =>
                breakdown.append(el("li", `${value.kind}: unavailable - ${value.reason || "unspecified"}`))
              );
              body.append(el("h3", "Score breakdown"), breakdown);
              details.append(summary, body);
              box.append(details);
            });
          }
        """
    }
}
