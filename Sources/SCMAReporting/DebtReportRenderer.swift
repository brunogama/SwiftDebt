import Foundation
import SCMACore

extension ReportRenderer {
    package func renderDebt(
        _ analysis: RankedDebtAnalysis,
        format: ReportFormat,
        graph: SwiftDependencyGraph? = nil
    ) throws -> String {
        let builder = DebtReportProjectionBuilder()
        switch format {
        case .debtJSON:
            return try encode(builder.nativeReport(from: analysis))
        case .debtMarkdown:
            return markdown(builder.nativeReport(from: analysis))
        case .debtDot:
            return dot(graph)
        case .debtText:
            return plain(builder.nativeReport(from: analysis))
        case .debtCompact:
            return compact(builder.nativeReport(from: analysis))
        case .debtmapJSON:
            return try encode(builder.projection(from: analysis))
        case .debtDashboard:
            return try renderDebtDashboard(builder.nativeReport(from: analysis))
        case .text, .json, .csv, .html, .diagnostics:
            throw AnalysisFailure.invalidConfiguration("Use a debt report format for ranked debt output")
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let encoded = String(bytes: data, encoding: .utf8) else {
            throw AnalysisFailure.invalidConfiguration("Unable to encode debt report as UTF-8")
        }
        return encoded + "\n"
    }

    private func markdown(_ report: DebtReport) -> String {
        var lines = [
            "# SwiftSCMA debt report",
            "",
            "Schema version: \(report.schemaVersion)",
            "Ranked items: \(report.summary.rankedItemCount)",
            "Unavailable evidence: " + String(report.summary.unavailableEvidenceCount)
        ]
        for priority in [Priority.critical, .high, .medium, .low] {
            let items = report.items.filter { $0.priority == priority }
            guard !items.isEmpty else { continue }
            lines += ["", "## \(title(priority.rawValue)) priority", ""]
            for (index, item) in items.enumerated() {
                lines += markdownLines(for: item)
                if index < items.index(before: items.endIndex) { lines.append("") }
            }
        }
        let unscored = report.items.filter { $0.priority == nil }
        if !unscored.isEmpty {
            lines += ["", "## Unscored", ""]
            for (index, item) in unscored.enumerated() {
                lines += markdownLines(for: item)
                if index < unscored.index(before: unscored.endIndex) { lines.append("") }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func markdownLines(for item: DebtReportItem) -> [String] {
        let available = item.evidence.filter(\.availability.isAvailable).count
        let unavailable = item.evidence.count - available
        var lines = [
            "### \(item.displayName)",
            "",
            "- ID: `\(item.id)`",
            "- Location: \(location(item.location))",
            "- Score: \(score(item.score))",
            "- Category: \(item.category)",
            "- Evidence: \(available) available, \(unavailable) unavailable",
            "- Why: \(item.explanation)",
            "- Action: " + item.recommendation
        ]
        if !item.scoreBreakdown.unavailableEvidence.isEmpty {
            lines.append("- Missing evidence:")
            for evidence in item.scoreBreakdown.unavailableEvidence {
                let reason = evidence.reason ?? "unspecified"
                let description = "  - \(evidence.kind) `\(evidence.evidenceID)`: \(reason)"
                lines.append(description)
            }
        }
        return lines
    }

    private func plain(_ report: DebtReport) -> String {
        var lines = ["PRIORITY | SCORE | ENTITY | LOCATION | CATEGORY | ACTION"]
        for item in report.items {
            let fields = [
                item.priority?.rawValue ?? "unscored",
                score(item.score),
                item.displayName,
                location(item.location),
                item.category,
                item.recommendation
            ]
            lines.append(fields.joined(separator: " | "))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func compact(_ report: DebtReport) -> String {
        report.items.map { item in
            let priority = item.priority?.rawValue ?? "unscored"
            let prefix = "\(priority) \(score(item.score))"
            let detail = "\(item.id) \(location(item.location)) - \(item.recommendation)"
            return "\(prefix) \(detail)"
        }.joined(separator: "\n") + "\n"
    }

    private func dot(_ graph: SwiftDependencyGraph?) -> String {
        guard let graph else { return "digraph SwiftSCMADebt {\n  rankdir=LR;\n}\n" }
        var lines = ["digraph SwiftSCMADebt {", "  rankdir=LR;"]
        for node in graph.nodes.sorted(by: { $0.id < $1.id }) {
            lines.append("  \"\(dotEscape(node.id))\" [label=\"\(dotEscape(node.displayName))\"];")
        }
        for edge in graph.edges.sorted(by: edgeOrder) {
            let target = edge.target ?? edge.unresolvedName.map { "unresolved:\($0)" } ?? "unresolved"
            let source = dotEscape(edge.source)
            let destination = dotEscape(target)
            let label = dotEscape(edge.kind.rawValue)
            lines.append("  \"\(source)\" -> \"\(destination)\" [label=\"\(label)\"];")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private func edgeOrder(_ lhs: SwiftGraphEdge, _ rhs: SwiftGraphEdge) -> Bool {
        if lhs.source != rhs.source { return lhs.source < rhs.source }
        if (lhs.target ?? "") != (rhs.target ?? "") { return (lhs.target ?? "") < (rhs.target ?? "") }
        if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
        return (lhs.unresolvedName ?? "") < (rhs.unresolvedName ?? "")
    }

    private func score(_ value: Double?) -> String {
        guard let value else { return "N/A" }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func location(_ location: DebtLocation) -> String {
        let file = location.file ?? "unknown"
        guard let line = location.line else { return file }
        return "\(file):\(line):\(location.column ?? 1)"
    }

    private func title(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }

    private func dotEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
