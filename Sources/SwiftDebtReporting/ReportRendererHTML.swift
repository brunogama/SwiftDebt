import Foundation
import SwiftDebtCore

extension ReportRenderer {
    package func html(_ report: AnalysisReport) throws -> String {
        return try ReportTemplate.render(
            named: "analysis-report", context: htmlContext(report)) + "\n"
    }

    private func htmlContext(_ report: AnalysisReport) -> [String: Any] {
        [
            "analysisState": report.complete ? "Complete analysis" : "INCOMPLETE ANALYSIS",
            "analyzedFileCount": report.analyzedFileCount,
            "inputFileCount": report.inputFileCount,
            "codeLineCount": report.codeLineCount,
            "typeScope": report.typeScope.rawValue,
            "scoringMode": report.scoringMode.rawValue,
            "modules": report.modules.joined(separator: ", "),
            "metrics": report.metrics.map(htmlMetricContext),
            "overallScore": number(report.overallScore),
            "overallScoreNote": report.overallScoreNote
                ?? "All ten metric scores are defined.",
            "findingCount": report.findings.count,
            "findings": report.findings.map(htmlFindingContext),
            "diagnostics": report.diagnostics.map(htmlDiagnosticContext),
            "engineVersion": report.engineVersion,
            "schemaVersion": report.schemaVersion,
        ]
    }

    private func htmlMetricContext(_ metric: MetricSummary) -> [String: Any] {
        [
            "id": metric.metric.rawValue,
            "title": metric.metric.title,
            "observationCount": metric.observations.count,
            "maximum": metric.maximum.map(String.init) ?? "-",
            "total": metric.total,
            "limit": metric.threshold.map { ">\($0)" } ?? "-",
            "violations": metric.violations,
            "score": number(metric.score),
            "measurementNote": metric.measurementNote ?? "",
            "scoreNote": metric.scoreNote ?? "",
            "observations": metric.observations.map {
                [
                    "entity": $0.entity, "file": $0.location.file, "line": $0.location.line,
                    "value": $0.value,
                ] as [String: Any]
            },
        ]
    }

    private func htmlFindingContext(_ finding: Finding) -> [String: Any] {
        [
            "metric": finding.metric.rawValue, "file": finding.location.file,
            "line": finding.location.line, "entity": finding.entity,
            "value": finding.value, "threshold": finding.threshold,
        ]
    }

    private func htmlDiagnosticContext(_ diagnostic: AnalysisDiagnostic) -> [String: Any] {
        [
            "file": diagnostic.location.file, "line": diagnostic.location.line,
            "severity": diagnostic.severity.rawValue, "message": diagnostic.message,
        ]
    }
}
