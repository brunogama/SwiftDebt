import Foundation
import SwiftDebtCore

package struct ReportRenderer {
    package init() {}

    package func render(_ report: AnalysisReport, format: ReportFormat, root: String) throws
        -> String
    {
        switch format {
        case .text: return text(report)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let encoded = try encoder.encode(report)
            guard let json = String(bytes: encoded, encoding: .utf8) else {
                throw AnalysisFailure.invalidConfiguration(
                    "Encoded analysis report is not valid UTF-8")
            }
            return json + "\n"
        case .csv: return csv(report)
        case .html: return try html(report)
        case .diagnostics: return diagnostics(report, root: root)
        case .debtJSON, .debtMarkdown, .debtDot, .debtText, .debtCompact, .debtmapJSON,
            .debtDashboard:
            throw AnalysisFailure.invalidConfiguration(
                "Debt report formats require debt analysis results")
        }
    }

    package func number(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func text(_ report: AnalysisReport) -> String {
        var rows = [
            "SwiftDebt \(report.engineVersion) - \(report.complete ? "complete" : "INCOMPLETE")",
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
                "WARNING: Experimental paper-derived scores are not validated quality grades. "
                    + "See docs/PAPER_MAPPING.md."
            )
        }
        for metric in report.metrics {
            if let note = metric.measurementNote {
                rows.append("\(metric.metric.rawValue): \(note)")
            }
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
                ? location.file
                : URL(fileURLWithPath: root).appendingPathComponent(location.file).path
            return "\(singleLine(absolute)):\(location.line):\(location.column)"
        }
        var lines = report.diagnostics.map {
            "\(prefix($0.location)): \($0.severity.rawValue): SwiftDebt \(singleLine($0.message))"
        }
        lines += report.findings.map {
            "\(prefix($0.location)): warning: SwiftDebt [\($0.metric.rawValue)] \(singleLine($0.entity)): \($0.value) exceeds \($0.threshold)"
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
                        String(item.location.line), String(item.location.column),
                        String(item.value),
                        metric.threshold.map(String.init) ?? "",
                        String(metric.threshold.map { item.value > $0 } ?? false),
                        metric.score.map { number($0) } ?? "",
                    ].joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private func singleLine(_ value: String) -> String {
        String(
            value.unicodeScalars.map {
                CharacterSet.controlCharacters.contains($0) ? " " : String($0)
            }.joined())
    }

    private func csvCell(_ value: String) -> String {
        // Prevent spreadsheet formula execution when opening source-controlled entity/path names.
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let unsafe = trimmed.first.map { "=+-@".contains($0) } ?? false
        let protected = unsafe || value.first == "\t" || value.first == "\r" ? "'" + value : value
        return "\"" + protected.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
