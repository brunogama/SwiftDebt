import Foundation
import SwiftDebtCore
import SwiftDebtReporting

struct RankedDebtAnalysisInput {
    let report: AnalysisReport
    let root: URL
    let options: DebtAnalysisOptions?
    let lcovPath: String?
    let referenceTime: Date?
    let gitExecutablePath: String?
    let profiler: AnalysisProfiler?
    let pluginEvidenceLimitations: Bool
}

extension AnalysisService {
    func rankedDebtAnalysis(
        for report: AnalysisReport,
        request: AnalysisRequest,
        workspace: PreparedAnalysis,
        profiler: AnalysisProfiler?
    ) -> RankedDebtAnalysis? {
        let options =
            request.debtAnalysisOptions ?? workspace.configuration.debtAnalysis
            ?? (request.enableDebtAnalysis || workspace.configuration.debtValidation != nil
                ? DebtAnalysisOptions() : nil)
        return makeRankedDebtAnalysis(
            RankedDebtAnalysisInput(
                report: report, root: workspace.root, options: options,
                lcovPath: request.lcovPath ?? workspace.configuration.lcovPath,
                referenceTime: request.debtReferenceTime
                    ?? workspace.configuration.debtReferenceTime,
                gitExecutablePath: request.gitExecutablePath,
                profiler: profiler,
                pluginEvidenceLimitations: request.pluginEvidenceLimitations))
    }

    func makeRankedDebtAnalysis(_ input: RankedDebtAnalysisInput) -> RankedDebtAnalysis? {
        guard let options = input.options else { return nil }
        let entities = input.report.debtItems.map(\.entity)
        let evidence =
            coverageEvidence(for: input, entities: entities)
            + historyEvidence(for: input, entities: entities)
        let merged = {
            input.profiler?.begin(.aggregation)
            defer { input.profiler?.end(.aggregation) }
            return merge(evidence: evidence, into: input.report.debtItems)
        }()
        return {
            input.profiler?.begin(.scoring)
            defer { input.profiler?.end(.scoring) }
            return DebtAnalysisBuilder(options: options).analyze(items: merged)
        }()
    }

    private func coverageEvidence(
        for input: RankedDebtAnalysisInput, entities: [DebtEntity]
    ) -> [DebtEvidence] {
        guard let lcovPath = input.lcovPath else {
            guard input.pluginEvidenceLimitations else { return [] }
            return unavailableCoverageEvidence(
                for: entities,
                reason:
                    "LCOV coverage is unavailable in SwiftPM plugin context unless an accessible "
                    + "coverage file is configured"
            )
        }
        input.profiler?.begin(.coverage)
        defer { input.profiler?.end(.coverage) }
        let url =
            (lcovPath as NSString).isAbsolutePath
            ? URL(fileURLWithPath: lcovPath) : input.root.appendingPathComponent(lcovPath)
        do {
            let lcov = LcovParser().parse(try String(contentsOf: url, encoding: .utf8))
            return CoverageMatcher().match(
                report: lcov, entities: entities, repositoryRoot: input.root.path
            ).evidence
        } catch {
            return unavailableCoverageEvidence(
                for: entities, reason: "LCOV unavailable: \(error)")
        }
    }

    private func historyEvidence(
        for input: RankedDebtAnalysisInput, entities: [DebtEntity]
    ) -> [DebtEvidence] {
        input.profiler?.begin(.repositoryHistory)
        defer { input.profiler?.end(.repositoryHistory) }
        if let referenceTime = input.referenceTime {
            return GitHistoryEvidenceProvider(gitExecutablePath: input.gitExecutablePath).evidence(
                for: GitHistoryEvidenceRequest(
                    repositoryRoot: input.root.path, referenceTime: referenceTime,
                    entities: entities)
            ).evidence
        }
        let reason =
            input.pluginEvidenceLimitations
            ? "Git history evidence is unavailable in SwiftPM plugin context without an explicit "
                + "reference time; configure debtReferenceTime in .swift-debt.json or pass "
                + "--debt-reference-time to the command plugin"
            : "Git history evidence requires an explicit reference time; pass "
                + "--debt-reference-time or configure debtReferenceTime in .swift-debt.json"
        return entities.flatMap { unavailableEvidence(for: $0, reason: reason) }
    }

    func merge(evidence: [DebtEvidence], into items: [DebtItem]) -> [DebtItem] {
        guard !evidence.isEmpty else { return items }
        let grouped = Dictionary(grouping: evidence) { evidence in
            entityID(for: evidence.id)
        }
        return items.map { item in
            let mergedEvidence = (item.evidence + grouped[item.id, default: []]).sorted {
                lhs, rhs in
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

    func entityID(for evidenceID: String) -> String {
        for marker in [":coverage:", ":git-history:"] {
            if let range = evidenceID.range(of: marker) {
                return String(evidenceID[..<range.lowerBound])
            }
        }
        return evidenceID
    }

    func unavailableCoverageEvidence(for entities: [DebtEntity], reason: String)
        -> [DebtEvidence]
    {
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

    func debtValidationFailed(
        _ validation: WorkspaceDebtValidation?,
        analysis: RankedDebtAnalysis?
    ) -> Bool {
        guard let validation, let analysis else { return false }
        return analysis.items.contains { item in
            guard let value = item.score.value else { return false }
            return value > validation.maxScore
        }
    }

    func debtValidationDiagnostics(
        _ validation: WorkspaceDebtValidation?,
        analysis: RankedDebtAnalysis?,
        root: URL
    ) -> String {
        guard let validation, let analysis else { return "" }
        let failures = analysis.items.compactMap { item -> String? in
            guard let value = item.score.value, value > validation.maxScore else { return nil }
            let location = item.item.entity.location
            let file = location.file ?? "."
            let absolute =
                (file as NSString).isAbsolutePath ? file : root.appendingPathComponent(file).path
            let line = location.line ?? 1
            let column = location.column ?? 1
            let score = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
            let limit = String(
                format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), validation.maxScore)
            return
                "\(absolute):\(line):\(column): warning: SwiftDebt [DEBT] \(item.item.entity.displayName): debt score \(score) exceeds \(limit)"
        }.sorted()
        return failures.isEmpty ? "" : failures.joined(separator: "\n") + "\n"
    }

    func write(_ content: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
