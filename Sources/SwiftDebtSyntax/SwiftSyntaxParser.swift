import Foundation
import SwiftDebtCore
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax

package struct SwiftSyntaxParser: SourceParsing {
    package init() {}

    package func parse(_ source: SourceUnit) -> ParsedSource {
        let tree = Parser.parse(source: source.content)
        let converter = SourceLocationConverter(fileName: source.path, tree: tree)
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: tree).map { diagnostic in
            let location = converter.location(for: diagnostic.position)
            return AnalysisDiagnostic(
                severity: diagnostic.diagMessage.severity == .error ? .error : .warning,
                message: diagnostic.message,
                location: SwiftDebtCore.SourceLocation(
                    file: source.path, line: location.line, column: location.column)
            )
        }
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            // Error recovery is useful to editors, but must not manufacture quality metrics.
            return ParsedSource(
                path: source.path, module: source.module, types: [], functions: [], closures: [],
                lines: [], topLevelVariables: 0, diagnostics: diagnostics)
        }
        let imports = ImportVisitor()
        imports.walk(tree)
        let collector = DeclarationCollector(
            source: source, converter: converter, imports: imports.modules)
        collector.walk(tree)
        return ParsedSource(
            path: source.path, module: source.module, types: collector.types,
            functions: collector.functions, closures: collector.closures,
            lines: collector.sourceLines.codeLines(tree),
            topLevelVariables: collector.topLevelVariables,
            diagnostics: diagnostics, riskFacts: collector.riskFacts
        )
    }
}
