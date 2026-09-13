import Foundation
import SCMACore
import SCMASyntax

public struct CoverageExplanationRequest: Sendable {
    public let path: String
    public let lcovPath: String
    public let manifestPath: String?
    public let configurationPath: String?
    public let exclude: [String]

    public init(
        path: String = ".",
        lcovPath: String,
        manifestPath: String? = nil,
        configurationPath: String? = nil,
        exclude: [String] = []
    ) {
        self.path = path
        self.lcovPath = lcovPath
        self.manifestPath = manifestPath
        self.configurationPath = configurationPath
        self.exclude = exclude
    }
}

public struct CoverageExplanationResult: Sendable {
    public let matching: CoverageMatchingResult
    public let standardOutput: String

    public init(matching: CoverageMatchingResult, standardOutput: String) {
        self.matching = matching
        self.standardOutput = standardOutput
    }
}

public struct CoverageExplanationService: Sendable {
    public init() {}

    public func run(_ request: CoverageExplanationRequest) throws -> CoverageExplanationResult {
        let discovery = SourceDiscovery()
        let analysisRequest = AnalysisRequest(
            path: request.path,
            manifestPath: request.manifestPath,
            configurationPath: request.configurationPath,
            exclude: request.exclude
        )
        let root = try discovery.root(for: analysisRequest)
        let configurationURL =
            request.configurationPath.map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent(".scma.json")
        var configuration = WorkspaceConfiguration()
        let hasConfiguration = FileManager.default.fileExists(atPath: configurationURL.path)
        if request.configurationPath != nil || hasConfiguration {
            let data = try Data(contentsOf: configurationURL)
            configuration = try JSONDecoder().decode(WorkspaceConfiguration.self, from: data)
        }
        _ = try configuration.analysisOptions(overrides: analysisRequest)
        let selection = try discovery.select(
            request: analysisRequest,
            root: root,
            excludes: configuration.exclude + request.exclude
        )
        let sources = try discovery.read(selection, maximumFileBytes: configuration.maximumFileBytes)
        let parser = SwiftSyntaxParser()
        let entities = sources
            .map { parser.parse($0) }
            .filter(\.isValid)
            .flatMap(entities)
            .sorted { $0.id < $1.id }
        let lcov = try String(contentsOf: URL(fileURLWithPath: request.lcovPath), encoding: .utf8)
        let report = LcovParser().parse(lcov)
        let matching = CoverageMatcher().match(report: report, entities: entities, repositoryRoot: root.path)
        return CoverageExplanationResult(
            matching: matching,
            standardOutput: CoverageMatcher().renderDiagnostics(matching.diagnostics)
        )
    }

    private func entities(for source: ParsedSource) -> [DebtEntity] {
        source.functions.map { function in
            DebtEntity(
                id: "callable:\(function.name)",
                displayName: function.name,
                level: .callable,
                location: DebtLocation(module: source.module, source: function.location)
            )
        }
    }
}
