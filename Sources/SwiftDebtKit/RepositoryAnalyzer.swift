import Foundation
import SwiftDebtCore

public enum RepositoryAnalysisFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case duplicateSourcePath(String)
    case emptyModule(String)
    case noSources

    public var description: String {
        switch self {
        case .duplicateSourcePath(let path): "Duplicate normalized repository source path: \(path)"
        case .emptyModule(let path): "Repository source module is empty for \(path)."
        case .noSources: "Repository analysis requires at least one Swift source."
        }
    }
}

public struct RepositoryAnalyzer: Sendable {
    public init() {}

    public func analyze(
        _ sources: [SourceUnit],
        configuration: RepositoryAnalysisConfiguration = .standard,
        versionControl: RepositoryVersionControlIdentity? = nil
    ) throws -> RepositoryEvidenceReport {
        let selected = try select(sources)
        let digest = try sourceDigest(selected)
        var inheritedIssues: [RepositoryEvidenceIssue] = []
        let byteCount = selected.reduce(into: 0) { total, source in
            let (next, overflow) = total.addingReportingOverflow(source.content.utf8.count)
            total = overflow ? Int.max : next
        }
        if selected.count > configuration.maximumSourceFiles {
            inheritedIssues.append(
                try RepositoryEvidenceIssue(
                    code: "source-file-budget-exceeded",
                    message:
                        "Repository analysis selected \(selected.count) files, exceeding the configured limit of \(configuration.maximumSourceFiles)."
                )
            )
        }
        if byteCount > configuration.maximumTotalSourceBytes {
            inheritedIssues.append(
                try RepositoryEvidenceIssue(
                    code: "source-byte-budget-exceeded",
                    message:
                        "Repository analysis selected \(byteCount) UTF-8 bytes, exceeding the configured limit of \(configuration.maximumTotalSourceBytes)."
                )
            )
        }

        let facts = inheritedIssues.isEmpty ? RepositorySyntaxExtractor().extract(selected) : RepositorySyntaxFacts()
        let parseErrorCount = facts.diagnostics.count { $0.severity == .error }
        if parseErrorCount > 0 {
            inheritedIssues.append(
                try RepositoryEvidenceIssue(
                    code: "parse-failed",
                    message:
                        "Repository analysis skipped syntax facts from \(parseErrorCount) parse-error diagnostics; absence is not established."
                )
            )
        }
        let dataClumps = try DataClumpsRepositoryRule().analyze(
            units: facts.dataClumpUnits,
            snapshotDigest: digest,
            configuration: configuration,
            inheritedIssues: inheritedIssues
        )
        let repeatedSwitches = try RepeatedSwitchesRepositoryRule().analyze(
            units: facts.repeatedSwitchUnits,
            conditionalSwitchLocations: facts.conditionalSwitchLocations,
            snapshotDigest: digest,
            configuration: configuration,
            inheritedIssues: inheritedIssues
        )
        let rules = [dataClumps, repeatedSwitches]
        let completeCount = rules.count { $0.completionState == .complete }
        let snapshot = RepositorySnapshotIdentity(
            sourceFiles: selected.map(\.path),
            contentDigest: digest,
            configuration: configuration,
            versionControl: versionControl
        )
        return RepositoryEvidenceReport(
            generator: "SwiftDebt \(SwiftDebtRelease.version)",
            snapshot: snapshot,
            rules: rules,
            diagnostics: facts.diagnostics,
            summary: RepositoryEvidenceSummary(
                sourceFileCount: selected.count,
                completeRuleCount: completeCount,
                incompleteRuleCount: rules.count - completeCount,
                detectionCount: rules.flatMap(\.detections).count,
                currentSnapshotNotice:
                    "Detections describe only this analyzed source snapshot and are not durable Findings or lifecycle state."
            )
        )
    }

    private func select(_ sources: [SourceUnit]) throws -> [SourceUnit] {
        guard !sources.isEmpty else { throw RepositoryAnalysisFailure.noSources }
        var paths = Set<String>()
        var selected: [SourceUnit] = []
        selected.reserveCapacity(sources.count)
        for source in sources {
            let path = try SourcePath(source.path).rawValue
            guard paths.insert(path).inserted else {
                throw RepositoryAnalysisFailure.duplicateSourcePath(path)
            }
            guard !source.module.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RepositoryAnalysisFailure.emptyModule(path)
            }
            selected.append(SourceUnit(path: path, module: source.module, content: source.content))
        }
        return selected.sorted { lhs, rhs in
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            return lhs.module < rhs.module
        }
    }

    private func sourceDigest(_ sources: [SourceUnit]) throws -> RepositoryDigest {
        var hasher = RepositorySHA256()
        hasher.updateFramed("swiftdebt-repository-snapshot-v1")
        for source in sources {
            hasher.updateFramed(source.path)
            hasher.updateFramed(source.module)
            hasher.updateFramed(source.content)
        }
        return try RepositoryDigest(value: hasher.finalizeHex())
    }
}
