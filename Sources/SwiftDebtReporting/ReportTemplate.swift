import Foundation
import Mustache
import SwiftDebtCore

enum ReportTemplate {
    static func render(named name: String, context: Any) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "mustache") else {
            throw AnalysisFailure.invalidConfiguration("Missing report template: \(name).mustache")
        }
        let data = try Data(contentsOf: url)
        guard let source = String(data: data, encoding: .utf8) else {
            throw AnalysisFailure.invalidConfiguration(
                "Report template is not valid UTF-8: \(name).mustache")
        }
        return try MustacheTemplate(string: source).render(context)
    }
}
