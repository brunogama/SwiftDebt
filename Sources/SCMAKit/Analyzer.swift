import SCMACore
import SCMASyntax

/// Reusable, in-memory boundary. No global state or service locator.
public struct Analyzer: Sendable {
    private let parser: any SourceParsing

    public init() { parser = SwiftSyntaxParser() }
    package init(parser: any SourceParsing) { self.parser = parser }

    public func analyze(
        _ sources: [SourceUnit], options: AnalysisOptions = .init(), jobs: Int = 1
    ) async throws -> AnalysisReport {
        try options.validate()
        guard (1...64).contains(jobs) else {
            throw AnalysisFailure.invalidConfiguration("jobs must be between 1 and 64")
        }
        guard !sources.isEmpty else { throw AnalysisFailure.noSources }
        guard Set(sources.map(\.path)).count == sources.count,
            sources.allSatisfy({ !$0.path.isEmpty && !$0.module.isEmpty })
        else {
            throw AnalysisFailure.invalidConfiguration(
                "Source paths must be unique and paths/modules must not be empty")
        }
        let parser = self.parser
        let parsed = try await withThrowingTaskGroup(of: ParsedSource.self) { group in
            var next = 0
            var results: [ParsedSource] = []
            results.reserveCapacity(sources.count)
            for _ in 0..<min(jobs, sources.count) {
                let source = sources[next]
                next += 1
                group.addTask {
                    try Task.checkCancellation()
                    return parser.parse(source)
                }
            }
            while let result = try await group.next() {
                try Task.checkCancellation()
                results.append(result)
                if next < sources.count {
                    let source = sources[next]
                    next += 1
                    group.addTask {
                        try Task.checkCancellation()
                        return parser.parse(source)
                    }
                }
            }
            return results
        }
        try Task.checkCancellation()
        return try MetricsCalculator().analyze(parsed, options: options)
    }
}
