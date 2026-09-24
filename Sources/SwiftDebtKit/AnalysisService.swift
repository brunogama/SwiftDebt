import Foundation
import SwiftDebtCore
import SwiftDebtReporting
import SwiftDebtSyntax

/// Filesystem/configuration/reporting composition root used by the CLI and both plugins.
public struct AnalysisService: Sendable {
    public init() {}

    public func run(_ request: AnalysisRequest) async throws -> AnalysisRunResult {
        let profiler = request.profileOutputPath == nil ? nil : AnalysisProfiler()
        let discovery = SourceDiscovery()
        let (root, configurationURL, configuration, options, selection, sources) = try {
            profiler?.begin(.discovery)
            defer { profiler?.end(.discovery) }
            let root = try discovery.root(for: request)
            let configurationURL =
                request.configurationPath.map { URL(fileURLWithPath: $0) }
                ?? root.appendingPathComponent(".swift-debt.json")
            var configuration = WorkspaceConfiguration()
            let hasConfiguration = FileManager.default.fileExists(atPath: configurationURL.path)
            if request.configurationPath != nil || hasConfiguration {
                do {
                    let data = try Data(contentsOf: configurationURL)
                    configuration = try JSONDecoder().decode(WorkspaceConfiguration.self, from: data)
                } catch let failure as AnalysisFailure {
                    throw AnalysisFailure.invalidConfiguration("\(configurationURL.path): \(failure)")
                } catch let failure as DecodingError {
                    throw AnalysisFailure.invalidConfiguration(
                        "\(configurationURL.path): \(decodingErrorDescription(failure))")
                } catch {
                    throw WorkspaceError("Unable to read configuration \(configurationURL.path): \(error)")
                }
            }
            let options = try configuration.analysisOptions(overrides: request)
            let selection = try discovery.select(
                request: request, root: root, excludes: configuration.exclude + request.exclude)
            let sources = try discovery.read(
                selection,
                maximumFileBytes: request.maximumFileBytes ?? configuration.maximumFileBytes
            )
            return (root, configurationURL, configuration, options, selection, sources)
        }()
        let format = request.format ?? configuration.format
        let ruleAnalysisSnapshot: AnalysisSnapshot?
        if format == .text {
            ruleAnalysisSnapshot = try RuleEngine().analyze(sources, using: ForceTryRule())
        } else {
            ruleAnalysisSnapshot = nil
        }
        let report = try await Analyzer().analyze(
            sources, options: options, jobs: request.jobs ?? configuration.jobs, phaseSink: profiler)
        let debtOptions =
            request.debtAnalysisOptions ?? configuration.debtAnalysis
            ?? (request.enableDebtAnalysis || configuration.debtValidation != nil ? DebtAnalysisOptions() : nil)
        let rankedDebtAnalysis = makeRankedDebtAnalysis(
            report: report,
            root: root,
            options: debtOptions,
            lcovPath: request.lcovPath ?? configuration.lcovPath,
            referenceTime: request.debtReferenceTime ?? configuration.debtReferenceTime,
            profiler: profiler,
            pluginEvidenceLimitations: request.pluginEvidenceLimitations
        )
        let debtValidationDiagnostics = debtValidationDiagnostics(
            configuration.debtValidation,
            analysis: rankedDebtAnalysis,
            root: root
        )
        let rendered: String = try {
            profiler?.begin(.rendering)
            defer { profiler?.end(.rendering) }
            if format.isDebtReportFormat {
                guard let rankedDebtAnalysis else {
                    throw AnalysisFailure.invalidConfiguration("Debt report formats require debtAnalysis configuration")
                }
                return try ReportRenderer().renderDebt(
                    rankedDebtAnalysis, format: format, graph: report.dependencyGraph)
            }
            let base = try ReportRenderer().render(report, format: format, root: root.path)
            if let ruleAnalysisSnapshot {
                return base + "\n" + RuleAnalysisRenderer().render(ruleAnalysisSnapshot)
            }
            return format == .diagnostics ? base + debtValidationDiagnostics : base
        }()
        var protectedPaths = Set(selection.entries.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path })
        protectedPaths.insert(configurationURL.resolvingSymlinksInPath().path)
        if let manifest = request.manifestPath {
            protectedPaths.insert(URL(fileURLWithPath: manifest).resolvingSymlinksInPath().path)
        }
        if let output = request.outputPath {
            let url = URL(fileURLWithPath: output).standardizedFileURL.resolvingSymlinksInPath()
            guard !protectedPaths.contains(url.path), url.pathExtension != "swift" else {
                throw WorkspaceError(
                    "Refusing to overwrite a source, configuration, manifest, or Swift file with a report")
            }
            try write(rendered, to: url)
            protectedPaths.insert(url.path)
        }
        let profile = profiler?.profile()
        if let profileOutput = request.profileOutputPath, let profile {
            let url = URL(fileURLWithPath: profileOutput).standardizedFileURL.resolvingSymlinksInPath()
            guard !protectedPaths.contains(url.path), url.pathExtension != "swift" else {
                throw WorkspaceError(
                    "Refusing to overwrite a source, configuration, manifest, report, or Swift file with a profile")
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(profile)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            protectedPaths.insert(url.path)
        }
        let failOnViolation = request.failOnViolation || configuration.failOnViolation
        let debtValidationFailed = debtValidationFailed(configuration.debtValidation, analysis: rankedDebtAnalysis)
        let ruleAnalysisIncomplete = ruleAnalysisSnapshot.map { !$0.isComplete } ?? false
        let status: Int32 =
            !report.complete || ruleAnalysisIncomplete
            ? 2 : ((failOnViolation && report.hasViolations) || debtValidationFailed ? 1 : 0)
        if let stamp = request.stampPath, status == 0 {
            let url = URL(fileURLWithPath: stamp).standardizedFileURL.resolvingSymlinksInPath()
            let content = "// Generated by SwiftDebt: analysis completed. No runtime declarations.\n"
            guard url.lastPathComponent == "SwiftDebt.analysis.swift", !protectedPaths.contains(url.path) else {
                throw WorkspaceError("Invalid build stamp path; expected an unprotected SwiftDebt.analysis.swift")
            }
            if FileManager.default.fileExists(atPath: url.path) {
                guard try String(contentsOf: url, encoding: .utf8) == content else {
                    throw WorkspaceError("Refusing to replace an existing non-SwiftDebt stamp")
                }
            }
            try write(content, to: url)
        }
        return AnalysisRunResult(
            report: report,
            standardOutput: request.outputPath == nil ? rendered : "",
            exitStatus: status,
            rankedDebtAnalysis: rankedDebtAnalysis,
            profile: profile,
            ruleAnalysisSnapshot: ruleAnalysisSnapshot
        )
    }

    private func makeRankedDebtAnalysis(
        report: AnalysisReport,
        root: URL,
        options: DebtAnalysisOptions?,
        lcovPath: String?,
        referenceTime: Date?,
        profiler: AnalysisProfiler?,
        pluginEvidenceLimitations: Bool
    ) -> RankedDebtAnalysis? {
        guard let options else { return nil }
        let entities = report.debtItems.map(\.entity)
        var evidence: [DebtEvidence] = []
        if let lcovPath {
            profiler?.begin(.coverage)
            let url =
                (lcovPath as NSString).isAbsolutePath
                ? URL(fileURLWithPath: lcovPath)
                : root.appendingPathComponent(lcovPath)
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                let lcov = LcovParser().parse(text)
                evidence +=
                    CoverageMatcher().match(report: lcov, entities: entities, repositoryRoot: root.path).evidence
            } catch {
                evidence += unavailableCoverageEvidence(for: entities, reason: "LCOV unavailable: \(error)")
            }
            profiler?.end(.coverage)
        } else if pluginEvidenceLimitations {
            evidence += unavailableCoverageEvidence(
                for: entities,
                reason:
                    "LCOV coverage is unavailable in SwiftPM plugin context unless an accessible coverage file is configured"
            )
        }
        profiler?.begin(.repositoryHistory)
        if let referenceTime {
            let history = GitHistoryEvidenceProvider().evidence(
                for: GitHistoryEvidenceRequest(
                    repositoryRoot: root.path,
                    referenceTime: referenceTime,
                    entities: entities
                )
            )
            evidence += history.evidence
        } else {
            let reason =
                pluginEvidenceLimitations
                ? "Git history evidence is unavailable in SwiftPM plugin context without an explicit reference time; configure debtReferenceTime in .swift-debt.json or pass --debt-reference-time to the command plugin"
                : "Git history evidence requires an explicit reference time; pass --debt-reference-time or configure debtReferenceTime in .swift-debt.json"
            evidence += entities.flatMap { unavailableEvidence(for: $0, reason: reason) }
        }
        profiler?.end(.repositoryHistory)
        let merged = {
            profiler?.begin(.aggregation)
            defer { profiler?.end(.aggregation) }
            return merge(evidence: evidence, into: report.debtItems)
        }()
        return {
            profiler?.begin(.scoring)
            defer { profiler?.end(.scoring) }
            return DebtAnalysisBuilder(options: options).analyze(items: merged)
        }()
    }

    private func merge(evidence: [DebtEvidence], into items: [DebtItem]) -> [DebtItem] {
        guard !evidence.isEmpty else { return items }
        let grouped = Dictionary(grouping: evidence) { evidence in
            entityID(for: evidence.id)
        }
        return items.map { item in
            let mergedEvidence = (item.evidence + grouped[item.id, default: []]).sorted { lhs, rhs in
                if lhs.id != rhs.id { return lhs.id < rhs.id }
                if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
                return lhs.rawValue < rhs.rawValue
            }
            return DebtItem(id: item.id, entity: item.entity, evidence: mergedEvidence)
        }.sorted { lhs, rhs in
            if lhs.entity.level.rawValue != rhs.entity.level.rawValue {
                return lhs.entity.level.rawValue < rhs.entity.level.rawValue
            }
            return lhs.id < rhs.id
        }
    }

    private func entityID(for evidenceID: String) -> String {
        for marker in [":coverage:", ":git-history:"] {
            if let range = evidenceID.range(of: marker) {
                return String(evidenceID[..<range.lowerBound])
            }
        }
        return evidenceID
    }

    private func unavailableCoverageEvidence(for entities: [DebtEntity], reason: String) -> [DebtEvidence] {
        entities.sorted(by: entityOrder).map { entity in
            DebtEvidence(
                id: "\(entity.id):coverage:lcov",
                kind: "coverage.lcov",
                availability: .unavailable(reason: reason),
                weight: 1,
                normalizedScore: nil,
                rawValue: "unavailable",
                location: entity.location,
                note: "Coverage provider unavailable; no zero-valued risk was fabricated."
            )
        }
    }

    private func debtValidationFailed(
        _ validation: WorkspaceDebtValidation?,
        analysis: RankedDebtAnalysis?
    ) -> Bool {
        guard let validation, let analysis else { return false }
        return analysis.items.contains { item in
            guard let value = item.score.value else { return false }
            return value > validation.maxScore
        }
    }

    private func debtValidationDiagnostics(
        _ validation: WorkspaceDebtValidation?,
        analysis: RankedDebtAnalysis?,
        root: URL
    ) -> String {
        guard let validation, let analysis else { return "" }
        let failures = analysis.items.compactMap { item -> String? in
            guard let value = item.score.value, value > validation.maxScore else { return nil }
            let location = item.item.entity.location
            let file = location.file ?? "."
            let absolute = (file as NSString).isAbsolutePath ? file : root.appendingPathComponent(file).path
            let line = location.line ?? 1
            let column = location.column ?? 1
            let score = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
            let limit = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), validation.maxScore)
            return
                "\(absolute):\(line):\(column): warning: SwiftDebt [DEBT] \(item.item.entity.displayName): debt score \(score) exceeds \(limit)"
        }.sorted()
        return failures.isEmpty ? "" : failures.joined(separator: "\n") + "\n"
    }

    private func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
