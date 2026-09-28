import Foundation
import SwiftDebtCore

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
        guard report.reportKind == "swiftdebt-report" else {
            throw AnalysisFailure.invalidConfiguration(
                "Unsupported debt report kind: \(report.reportKind)")
        }
        let json = try encodeDashboardJSON(report)
        return try dashboardDocument(reportJSON: escapeScriptJSON(json))
    }

    private func encodeDashboardJSON(_ report: DebtReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(report)
        guard let json = String(bytes: encoded, encoding: .utf8) else {
            throw AnalysisFailure.invalidConfiguration("Encoded debt report is not valid UTF-8")
        }
        return json
    }

    private func escapeScriptJSON(_ value: String) -> String {
        value.replacingOccurrences(of: "<", with: "\\u003C")
            .replacingOccurrences(of: ">", with: "\\u003E")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }

    private func dashboardDocument(reportJSON: String) throws -> String {
        try ReportTemplate.render(
            named: "debt-dashboard",
            context: [
                "reportJSON": reportJSON,
                "applicationScript": DebtDashboardApplication.script,
            ]) + "\n"
    }
}
