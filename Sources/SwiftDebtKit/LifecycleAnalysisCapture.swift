import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle

enum LifecycleSelectionKind: String, Sendable {
    case directory
    case file
    case manifest
}

struct LifecycleAnalysisCapture: Sendable {
    let sourceIdentity: SnapshotSourceIdentity
    let scope: ObservationScope
    let gitSnapshot: LifecycleGitSnapshot
    let selectionKind: LifecycleSelectionKind
    let exclusions: [String]
    let maximumFileBytes: Int
    let sourceSelection: SourceSelectionEvidence?
    let sourceRenames: [SourceRenameEvidence]
    let sourceDeletions: [SourceDeletionEvidence]

    init(
        selection: SourceDiscovery.Selection,
        sources: [SourceUnit],
        exclusions: [String],
        maximumFileBytes: Int,
        gitBeforeRead: LifecycleGitSnapshot,
        gitAfterRead: LifecycleGitSnapshot
    ) throws {
        guard gitBeforeRead == gitAfterRead else {
            throw LifecycleAnalysisError.sourceChangedDuringCapture
        }
        let digest = try LifecycleCanonicalDigest.sourceUnits(sources)
        self.sourceIdentity = gitAfterRead.sourceIdentity(contentDigest: digest)
        self.gitSnapshot = gitAfterRead
        self.selectionKind = selection.kind
        self.exclusions = Self.normalized(exclusions)
        self.maximumFileBytes = maximumFileBytes
        self.sourceSelection = try Self.sourceSelection(
            selection: selection,
            exclusions: exclusions,
            gitSnapshot: gitAfterRead
        )
        switch gitAfterRead {
        case .available(_, _, _, _, _, let sourceRenames, let sourceDeletions):
            self.sourceRenames = sourceRenames
            self.sourceDeletions = sourceDeletions
        case .unavailable:
            self.sourceRenames = []
            self.sourceDeletions = []
        }
        self.scope = try Self.scope(
            selection: selection,
            exclusions: exclusions,
            gitSnapshot: gitAfterRead
        )
    }

    private static func normalized(_ exclusions: [String]) -> [String] {
        Set(exclusions.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 }).sorted()
    }

    private static func sourceSelection(
        selection: SourceDiscovery.Selection,
        exclusions: [String],
        gitSnapshot: LifecycleGitSnapshot
    ) throws -> SourceSelectionEvidence? {
        guard case .available(let repositoryRoot, _, _, _, _, _, _) = gitSnapshot else {
            return nil
        }
        let repositoryURL = URL(fileURLWithPath: repositoryRoot).standardizedFileURL.resolvingSymlinksInPath()
        let selectionRoot = selection.root.standardizedFileURL.resolvingSymlinksInPath()
        guard isWithin(selectionRoot, root: repositoryURL) else {
            throw LifecycleAnalysisError.gitInspectionFailed(
                "The selected source root is outside the captured Git repository."
            )
        }
        let relativeRoot: SourcePath? =
            selectionRoot.path == repositoryURL.path
            ? nil
            : try SourcePath(relativePath(selectionRoot, root: repositoryURL))
        let canonicalExclusions = normalized(exclusions).compactMap { exclusion -> SourcePath? in
            guard let path = try? SourcePath(exclusion), path.rawValue == exclusion else {
                return nil
            }
            return path
        }
        let exclusionPaths = try canonicalExclusions.map { exclusion -> SourcePath in
            let path =
                relativeRoot.map { $0.rawValue + "/" + exclusion.rawValue }
                ?? exclusion.rawValue
            return try SourcePath(path)
        }
        let kind: SourceSelectionKind =
            switch selection.kind {
            case .directory: .directory
            case .file: .file
            case .manifest: .manifest
            }
        return try SourceSelectionEvidence(
            kind: kind,
            repositoryRelativeRoot: relativeRoot,
            excludedPathPrefixes: exclusionPaths
        )
    }

    private static func scope(
        selection: SourceDiscovery.Selection,
        exclusions: [String],
        gitSnapshot: LifecycleGitSnapshot
    ) throws -> ObservationScope {
        var limitations: [String] = []
        switch selection.kind {
        case .directory: break
        case .file: limitations.append("one explicit source file was selected")
        case .manifest: limitations.append("an explicit source manifest was selected")
        }
        if !exclusions.isEmpty { limitations.append("configured exclusions narrowed source coverage") }
        if selection.skippedSymbolicLinks { limitations.append("symbolic-link entries were not followed") }
        if selection.skippedPackageManifest { limitations.append("Package.swift was excluded from source coverage") }
        if selection.skippedSourceDirectories {
            limitations.append("source directories were skipped by discovery policy")
        }
        switch gitSnapshot {
        case .available(let repositoryRoot, _, _, _, _, _, _):
            if repositoryRoot != selection.root.path {
                limitations.append("the analysis root is below the Git repository root")
            }
        case .unavailable:
            limitations.append("a Git repository boundary was unavailable")
        }
        guard !limitations.isEmpty else { return .repository }
        return .partial(
            try LifecycleReason(
                code: "partial-source-selection",
                message: limitations.joined(separator: "; ") + "."
            )
        )
    }
}
