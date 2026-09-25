import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax

extension LifecycleIntroductionService {
    func observe(
        revision: GitRevisionID,
        parents: [GitRevisionID],
        repositoryURL: URL,
        maximumFileBytes: Int
    ) throws -> ObservationSnapshot {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-debt-introduction-\(UUID().uuidString)",
            isDirectory: true
        )
        let archiveURL = temporary.appendingPathComponent("revision.tar")
        let checkoutURL = temporary.appendingPathComponent("checkout", isDirectory: true)
        try FileManager.default.createDirectory(at: checkoutURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        try require(
            executable: "/usr/bin/env",
            arguments: [
                "git", "-C", repositoryURL.path, "archive", "--format=tar",
                "--output", archiveURL.path, revision.rawValue,
            ],
            directory: repositoryURL
        )
        try require(
            executable: "/usr/bin/env",
            arguments: ["tar", "-xf", archiveURL.path, "-C", checkoutURL.path],
            directory: temporary
        )

        let discovery = SourceDiscovery()
        let request = AnalysisRequest(path: checkoutURL.path, maximumFileBytes: maximumFileBytes)
        let root = try discovery.root(for: request)
        let selection = try discovery.select(request: request, root: root, excludes: [])
        let sources = try discovery.read(selection, maximumFileBytes: maximumFileBytes)
        guard !sources.isEmpty else {
            throw WorkspaceError("Revision \(revision.rawValue) contains no selected Swift SourceUnits")
        }
        let analysis = try RuleEngine().analyze(sources, using: BuiltInRuleCatalog.all)
        let emptyStatusDigest = LifecycleSHA256.hexDigest(Data())
        let historicalGitSnapshot = LifecycleGitSnapshot.available(
            repositoryRoot: root.path,
            revision: revision,
            workingTreeState: .clean,
            parentRevisions: parents,
            statusDigest: emptyStatusDigest,
            sourceRenames: [],
            sourceDeletions: []
        )
        let capture = try LifecycleAnalysisCapture(
            selection: selection,
            sources: sources,
            exclusions: [],
            maximumFileBytes: maximumFileBytes,
            gitBeforeRead: historicalGitSnapshot,
            gitAfterRead: historicalGitSnapshot
        )
        let capabilities = [try SnapshotCapability(name: "syntax-analysis", state: .available)]
        let effectiveConfiguration = try LifecycleCanonicalDigest.effectiveConfiguration(
            analysis: analysis,
            capture: capture
        )
        let configuration = try effectiveConfiguration.fingerprint()
        let snapshotID = try LifecycleCanonicalDigest.snapshotID(
            sourceIdentity: capture.sourceIdentity,
            scope: capture.scope,
            configuration: configuration,
            rules: analysis.ruleDescriptors,
            capabilities: capabilities,
            engineVersion: SwiftDebtRelease.version,
            sourceSelection: capture.sourceSelection,
            sourceRenames: capture.sourceRenames,
            sourceDeletions: capture.sourceDeletions
        )
        return try ObservationSnapshot(
            id: snapshotID,
            provenance: SnapshotProvenance(
                sourceIdentity: capture.sourceIdentity,
                scope: capture.scope,
                configurationFingerprint: configuration,
                effectiveConfiguration: effectiveConfiguration,
                capabilities: capabilities,
                engineVersion: SwiftDebtRelease.version,
                lineage: try LineagePosition(
                    lineageID: LineageID("history-\(revision.rawValue)"),
                    sequence: 1
                ),
                sourceSelection: capture.sourceSelection,
                sourceRenames: capture.sourceRenames,
                sourceDeletions: capture.sourceDeletions
            ),
            analysis: analysis
        )
    }

}
