import Foundation
import SCMACore

package struct ReportRenderer {
    package init() {}

    package func render(_ report: AnalysisReport, format: ReportFormat, root: String) throws -> String {
        switch format {
        case .text: return text(report)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
        case .csv: return csv(report)
        case .html: return html(report)
        case .diagnostics: return diagnostics(report, root: root)
        case .debtJSON, .debtMarkdown, .debtDot, .debtText, .debtCompact, .debtmapJSON, .debtDashboard:
            throw AnalysisFailure.invalidConfiguration("Debt report formats require debt analysis results")
        }
    }

    private func number(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func text(_ report: AnalysisReport) -> String {
        var rows = [
            "SwiftSCMA \(report.engineVersion) - \(report.complete ? "complete" : "INCOMPLETE")",
            "Files: \(report.analyzedFileCount)/\(report.inputFileCount) | Code lines: \(report.codeLineCount) | Functions: \(report.functionCount)",
            "Type scope: \(report.typeScope.rawValue) | Scoring: \(report.scoringMode.rawValue) | Modules: \(report.modules.joined(separator: ", "))",
            "METRIC  ENTITIES  MAX  TOTAL  LIMIT(>)  VIOLATIONS  SCORE",
        ]
        rows += report.metrics.map { metric in
            "\(metric.metric.rawValue)  \(metric.observations.count)  \(metric.maximum.map(String.init) ?? "N/A")"
                + "  \(metric.total)  \(metric.threshold.map(String.init) ?? "N/A")  \(metric.violations)  \(number(metric.score))"
        }
        rows.append("Overall score: \(number(report.overallScore))")
        if let note = report.overallScoreNote { rows.append(note) }
        if report.scoringMode != .none {
            rows.append(
                "WARNING: Experimental paper-derived scores are not validated quality grades. See docs/PAPER_MAPPING.md."
            )
        }
        for metric in report.metrics {
            if let note = metric.measurementNote { rows.append("\(metric.metric.rawValue): \(note)") }
        }
        for diagnostic in report.diagnostics {
            rows.append(
                "\(diagnostic.location.file):\(diagnostic.location.line): \(diagnostic.severity.rawValue): \(diagnostic.message)"
            )
        }
        for finding in report.findings {
            rows.append(
                "\(finding.location.file):\(finding.location.line): \(finding.metric.rawValue) \(finding.value) > \(finding.threshold) - \(finding.entity)"
            )
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func diagnostics(_ report: AnalysisReport, root: String) -> String {
        func prefix(_ location: SourceLocation) -> String {
            let absolute =
                (location.file as NSString).isAbsolutePath
                ? location.file : URL(fileURLWithPath: root).appendingPathComponent(location.file).path
            return "\(singleLine(absolute)):\(location.line):\(location.column)"
        }
        var lines = report.diagnostics.map {
            "\(prefix($0.location)): \($0.severity.rawValue): SCMA \(singleLine($0.message))"
        }
        lines += report.findings.map {
            "\(prefix($0.location)): warning: SCMA [\($0.metric.rawValue)] \(singleLine($0.entity)): \($0.value) exceeds \($0.threshold)"
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    private func csv(_ report: AnalysisReport) -> String {
        var rows = ["metric,entity,file,line,column,value,threshold,violation,score"]
        for metric in report.metrics {
            for item in metric.observations {
                rows.append(
                    [
                        metric.metric.rawValue, csvCell(item.entity), csvCell(item.location.file),
                        String(item.location.line), String(item.location.column), String(item.value),
                        metric.threshold.map(String.init) ?? "",
                        String(metric.threshold.map { item.value > $0 } ?? false),
                        metric.score.map { number($0) } ?? "",
                    ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func html(_ report: AnalysisReport) -> String {
        let metrics = report.metrics.map { metric in
            """
            <tr><th scope="row">\(metric.metric.rawValue)</th><td>\(escape(metric.metric.title))</td>
            <td>\(metric.observations.count)</td><td>\(metric.maximum.map(String.init) ?? "-")</td>
            <td>\(metric.total)</td><td>\(metric.threshold.map { "&gt;\($0)" } ?? "-")</td>
            <td>\(metric.violations)</td><td>\(number(metric.score))</td></tr>
            """
        }.joined(separator: "\n")
        let details = report.metrics.map { metric in
            let rows = metric.observations.map {
                "<tr><td>\(escape($0.entity))</td><td>\(escape($0.location.file)):\($0.location.line)</td><td>\($0.value)</td></tr>"
            }.joined(separator: "\n")
            return """
                <details><summary>\(metric.metric.rawValue) · \(metric.observations.count) observations</summary>
                <p>\(escape(metric.measurementNote ?? ""))</p><p>\(escape(metric.scoreNote ?? ""))</p>
                <div class="scroll"><table><thead><tr><th>Entity</th><th>Location</th><th>Value</th></tr></thead>
                <tbody>\(rows)</tbody></table></div></details>
                """
        }.joined(separator: "\n")
        let diagnosticRows = report.diagnostics.map {
            "<li>\(escape($0.location.file)):\($0.location.line) - \($0.severity.rawValue): \(escape($0.message))</li>"
        }.joined()
        let findings = report.findings.map {
            "<li><strong>\($0.metric.rawValue)</strong> \(escape($0.location.file)):\($0.location.line) - \(escape($0.entity)): \($0.value) &gt; \($0.threshold)</li>"
        }.joined()
        return """
            <!doctype html>
            <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
            <title>SwiftSCMA analysis</title><style>
            :root{color-scheme:light dark}body{font:16px/1.55 system-ui,sans-serif;max-width:1180px;margin:3rem auto;padding:0 1.5rem}
            h1{font-size:2.2rem;margin-bottom:.3rem}h2{margin-top:2.2rem}.meta{opacity:.75}.notice{border-left:4px solid #c88925;padding:1rem;background:#c8892515}
            .scroll{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:.9rem}th,td{text-align:left;padding:.7rem;border-bottom:1px solid #80808050;vertical-align:top}
            thead{background:#80808015}td{font-variant-numeric:tabular-nums}details{margin:1rem 0;padding:.6rem;border:1px solid #80808050;border-radius:6px}
            summary{cursor:pointer;font-weight:600}li{margin:.5rem 0}footer{margin-top:3rem;border-top:1px solid #80808050;padding-top:1rem;opacity:.7}
            </style></head><body><header><p class="meta">STATIC ANALYSIS / SCMA PAPER IMPLEMENTATION</p><h1>SwiftSCMA</h1>
            <p>\(report.complete ? "Complete analysis" : "INCOMPLETE ANALYSIS") · \(report.analyzedFileCount)/\(report.inputFileCount) files · \(report.codeLineCount) code lines</p>
            <p class="meta">Type scope: \(report.typeScope.rawValue) · Scoring: \(report.scoringMode.rawValue) · Modules: \(escape(report.modules.joined(separator: ", ")))</p></header>
            <p class="notice">Raw metrics are the primary result. Paper-derived scores are experimental, not validated quality grades.
            Coupling and field usage are syntactic estimates. Clone detection is a native substitute for Lizard.</p>
            <h2>Metrics</h2><div class="scroll"><table><thead><tr><th>ID</th><th>Metric</th><th>Entities</th><th>Maximum</th><th>Total</th><th>Limit</th><th>Violations</th><th>Score</th></tr></thead><tbody>\(metrics)</tbody></table></div>
            <p><strong>Overall: \(number(report.overallScore))</strong> · \(escape(report.overallScoreNote ?? "All ten metric scores are defined."))</p>
            <h2>Findings (\(report.findings.count))</h2><ul>\(findings)</ul>
            <h2>Analysis diagnostics</h2><ul>\(diagnosticRows)</ul>
            <h2>Observation details</h2>\(details)
            <footer>SwiftSCMA \(report.engineVersion) · Report schema \(report.schemaVersion) · Self-contained report; no scripts, analytics, or network assets.</footer>
            </body></html>
            """ + "\n"
    }

    private func singleLine(_ value: String) -> String {
        String(value.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined())
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&#39;")
    }

    private func csvCell(_ value: String) -> String {
        // Prevent spreadsheet formula execution when opening source-controlled entity/path names.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsafe = trimmed.first.map { "=+-@".contains($0) } ?? false
        let protected = unsafe || value.first == "\t" || value.first == "\r" ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
