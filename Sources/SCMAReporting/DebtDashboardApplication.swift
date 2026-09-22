import SCMACore

enum DebtDashboardApplication {
    static var script: String {
        """
        (() => {
          "use strict";
          const reportSchemaVersion = \(DebtReportSchema.currentVersion);
          const comparisonSchemaVersion = \(DebtReportComparisonSchema.currentVersion);
          const q = id => document.getElementById(id);
          const el = (name, value, className) => {
            const element = document.createElement(name);
            if (className) element.className = className;
            if (value !== undefined) element.textContent = value;
            return element;
          };
          const state = { priority: "all", category: "all", level: "all", query: "" };
          let report = null;
          let comparison = null;

          function location(value) {
            if (!value) return "unknown";
            const parts = [value.file || "unknown"];
            if (value.line) parts.push(value.line);
            if (value.column) parts.push(value.column);
            return parts.join(":");
          }

          function score(value) {
            return value === null || value === undefined ? "N/A" : String(value);
          }

          function text(value) {
            return value === null || value === undefined ? "" : String(value);
          }

          function signed(value) {
            if (value === null || value === undefined) return "N/A";
            return value > 0 ? `+${value}` : String(value);
          }

          function validateReport(value) {
            if (!value || value.reportKind !== "swiftscma-debt-report"
                || value.schemaVersion !== reportSchemaVersion || !Array.isArray(value.items)) {
              throw new Error(`Expected SwiftSCMA debt report schema version ${reportSchemaVersion}`);
            }
            return value;
          }

          function validateComparison(value) {
            const validItems = value && value.itemChanges
              && Array.isArray(value.itemChanges.added)
              && Array.isArray(value.itemChanges.removed)
              && Array.isArray(value.itemChanges.changed)
              && Array.isArray(value.itemChanges.unchangedIDs);
            const validAggregations = value && value.aggregationChanges
              && Array.isArray(value.aggregationChanges.added)
              && Array.isArray(value.aggregationChanges.removed)
              && Array.isArray(value.aggregationChanges.changed)
              && Array.isArray(value.aggregationChanges.unchangedIDs);
            if (!value || value.schemaVersion !== comparisonSchemaVersion
                || value.beforeReportSchemaVersion !== reportSchemaVersion
                || value.afterReportSchemaVersion !== reportSchemaVersion
                || !value.summary || !validItems || !validAggregations || !value.missingEvidence) {
              throw new Error(`Expected SwiftSCMA debt report comparison schema version ${comparisonSchemaVersion}`);
            }
            return value;
          }

          function setStatus(message) {
            q("status").textContent = message;
          }

        \(reportFunctions)
        \(graphFunction)
        \(comparisonFunctions)

          function render() {
            fillSelect("priority-filter", priorities(report), "All priorities");
            fillSelect("category-filter", categories(report), "All categories");
            fillSelect("level-filter", levels(report), "All levels");
            q("report-title").textContent = `${report.generator || "SwiftSCMA"} schema ${report.schemaVersion} - ${report.items.length} ranked items`;
            const items = filteredItems();
            renderSummary();
            renderTable(items);
            renderDrilldown(items);
            renderGraph();
            renderComparison();
            setStatus(`Showing ${items.length} of ${report.items.length} ranked items.`);
          }

          function loadFile(input, validator, onLoad) {
            const file = input.files && input.files[0];
            if (!file) return;
            const reader = new FileReader();
            reader.onload = () => {
              try {
                onLoad(validator(JSON.parse(String(reader.result))));
                setStatus(`Loaded ${file.name}.`);
              } catch (error) {
                setStatus(error.message);
              }
            };
            reader.onerror = () => setStatus(`Could not read ${file.name}.`);
            reader.readAsText(file);
          }

          q("report-input").addEventListener("change", event => loadFile(
            event.target,
            validateReport,
            value => {
              report = value;
              comparison = null;
              render();
            }
          ));
          q("comparison-input").addEventListener("change", event => loadFile(
            event.target,
            validateComparison,
            value => {
              comparison = value;
              renderComparison();
            }
          ));
          q("priority-filter").addEventListener("change", event => {
            state.priority = event.target.value;
            render();
          });
          q("category-filter").addEventListener("change", event => {
            state.category = event.target.value;
            render();
          });
          q("level-filter").addEventListener("change", event => {
            state.level = event.target.value;
            render();
          });
          q("query-filter").addEventListener("input", event => {
            state.query = event.target.value;
            render();
          });
          document.addEventListener("keydown", event => {
            if (event.key === "/" && document.activeElement !== q("query-filter")) {
              event.preventDefault();
              q("query-filter").focus();
            }
            if (event.key === "Escape") {
              q("query-filter").value = "";
              state.query = "";
              render();
            }
          });

          try {
            report = validateReport(JSON.parse(q("swiftscma-initial-report").textContent));
            render();
          } catch (error) {
            setStatus(error.message);
          }
        })();
        """
    }
}
