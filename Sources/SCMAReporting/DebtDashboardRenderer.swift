import Foundation
import SCMACore

extension ReportRenderer {
    package func renderDebtDashboard(from data: Data) throws -> String {
        try renderDebtDashboard(JSONDecoder().decode(DebtReport.self, from: data))
    }

    package func renderDebtDashboard(_ report: DebtReport) throws -> String {
        guard report.schemaVersion == DebtReportSchema.currentVersion else {
            throw AnalysisFailure.invalidConfiguration(
                "Unsupported debt report schema version: \(report.schemaVersion)"
            )
        }
        guard report.reportKind == "swiftscma-debt-report" else {
            throw AnalysisFailure.invalidConfiguration("Unsupported debt report kind: \(report.reportKind)")
        }
        let json = try encodeDashboardJSON(report)
        return dashboardDocument(reportJSON: escapeScriptJSON(json))
    }

    private func encodeDashboardJSON(_ report: DebtReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    private func escapeScriptJSON(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }

    private func dashboardDocument(reportJSON: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'none'; img-src 'none'; base-uri 'none'; form-action 'none'">
        <title>SwiftSCMA debt dashboard</title>
        <style>
        :root{color-scheme:light dark;--line:#80808055;--soft:#80808018;--accent:#2463eb;--danger:#b42318;--warn:#b54708}body{font:16px/1.5 system-ui,sans-serif;max-width:1260px;margin:0 auto;padding:1.5rem;color:CanvasText;background:Canvas}.skip{position:absolute;left:-999px}.skip:focus{left:1rem;top:1rem;background:Canvas;padding:.5rem;border:2px solid var(--accent)}header{display:grid;gap:.35rem;margin:1rem 0 1.5rem}h1{font-size:2.25rem;margin:.2rem 0}h2{margin-top:2rem}.meta{opacity:.75}.panel{border:1px solid var(--line);border-radius:12px;padding:1rem;background:var(--soft)}.controls{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:.8rem;margin:1rem 0}.cards,.layout{display:grid;gap:1rem}.cards{grid-template-columns:repeat(auto-fit,minmax(150px,1fr))}.layout{grid-template-columns:minmax(0,1.5fr) minmax(280px,.9fr);align-items:start}.card{border:1px solid var(--line);border-radius:10px;padding:1rem}.scroll{overflow:auto}label{font-weight:700;display:grid;gap:.25rem}select,input,button{font:inherit;padding:.55rem;border:1px solid var(--line);border-radius:8px;background:Canvas;color:CanvasText}button{cursor:pointer}.status{min-height:1.5rem}.badge{border-radius:999px;padding:.15rem .45rem;background:var(--soft);white-space:nowrap}.critical{color:var(--danger);font-weight:700}.high{color:var(--warn);font-weight:700}table{width:100%;border-collapse:collapse;font-size:.92rem}th,td{text-align:left;border-bottom:1px solid var(--line);padding:.65rem;vertical-align:top}thead{background:var(--soft)}tr:target{outline:3px solid var(--accent)}details{border:1px solid var(--line);border-radius:10px;padding:.75rem;margin:.75rem 0}summary{cursor:pointer;font-weight:700}.graph{display:grid;gap:.5rem}.edge{display:flex;gap:.5rem;align-items:center}.edge:before{content:"";width:2rem;border-top:2px solid var(--accent)}footer{margin:2rem 0 1rem;border-top:1px solid var(--line);padding-top:1rem}.empty{opacity:.75}@media (max-width:860px){.layout{grid-template-columns:1fr}}
        </style>
        </head>
        <body>
        <a class="skip" href="#items">Skip to ranked debt items</a>
        <header>
        <p class="meta">PRESENTATION WORKFLOW / VERSIONED DEBT REPORT</p>
        <h1>SwiftSCMA debt dashboard</h1>
        <p id="report-title" class="meta">Loading embedded report.</p>
        </header>
        <main id="app" tabindex="-1">
        <section class="panel" aria-labelledby="loading-heading">
        <h2 id="loading-heading">Load reports</h2>
        <p>Open this file locally, or load another debt JSON report without running analysis.</p>
        <div class="controls">
        <label>Debt report JSON<input id="report-input" type="file" accept="application/json,.json"></label>
        <label>Comparison report JSON<input id="comparison-input" type="file" accept="application/json,.json"></label>
        <label>Priority filter<select id="priority-filter"><option value="all">All priorities</option></select></label>
        <label>Category filter<select id="category-filter"><option value="all">All categories</option></select></label>
        <label>File/type/function filter<select id="level-filter"><option value="all">All levels</option></select></label>
        <label>Search<input id="query-filter" type="search" placeholder="Filter by item, file, or evidence"></label>
        </div>
        <p id="status" class="status" role="status" aria-live="polite"></p>
        </section>
        <section aria-labelledby="summary-heading"><h2 id="summary-heading">Ranked overview</h2><div id="summary" class="cards"></div></section>
        <div class="layout">
        <section id="items" aria-labelledby="items-heading"><h2 id="items-heading">Debt items</h2><div id="item-table" class="scroll"></div><div id="drilldown"></div></section>
        <aside>
        <section aria-labelledby="graph-heading"><h2 id="graph-heading">Dependency and call graph</h2><div id="graph" class="panel graph"></div></section>
        <section aria-labelledby="comparison-heading"><h2 id="comparison-heading">Comparison</h2><div id="comparison" class="panel"></div></section>
        </aside>
        </div>
        </main>
        <footer>Self-contained dashboard; no hosted service, telemetry, or network assets. Scores, priorities, evidence, source locations, and graph facts are read from the versioned report artifacts.</footer>
        <script id="swiftscma-initial-report" type="application/json">
        \(reportJSON)
        </script>
        <script>
        \(DebtDashboardApplication.script)
        </script>
        </body>
        </html>
        """ + "\n"
    }
}
