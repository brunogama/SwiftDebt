import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax

extension LifecycleIntroductionService {
    struct HistoricalObservationResult: Sendable {
        let observation: ObservationSnapshot
        let reused: Bool
    }

    func observe(
        revision: GitRevisionID,
        parents: [GitRevisionID],
        repositoryURL: URL,
        maximumFileBytes: Int,
        reuseCandidates: [ObservationSnapshot]
    ) throws -> HistoricalObservationResult {
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
        let builtInRules = BuiltInRuleCatalog.all
        let rules = try currentRuleDescriptors(using: builtInRules)
        let capabilities = [try SnapshotCapability(name: "syntax-analysis", state: .available)]
        let selectionKind: SourceSelectionKind =
            switch capture.selectionKind {
            case .directory: .directory
            case .file: .file
            case .manifest: .manifest
            }
        let effectiveConfiguration = try LifecycleEffectiveConfiguration(
            sourceSelectionKind: selectionKind,
            excludedSourcePrefixes: capture.exclusions,
            maximumFileBytes: capture.maximumFileBytes,
            selectedRuleIdentities: rules.descriptors.map(\.identity)
        )
        let configuration = try effectiveConfiguration.fingerprint()
        let snapshotID = try LifecycleCanonicalDigest.snapshotID(
            sourceIdentity: capture.sourceIdentity,
            scope: capture.scope,
            configuration: configuration,
            rules: rules.descriptors,
            capabilities: capabilities,
            engineVersion: SwiftDebtRelease.version,
            sourceSelection: capture.sourceSelection,
            sourceRenames: capture.sourceRenames,
            sourceDeletions: capture.sourceDeletions
        )
        let provenance = try SnapshotProvenance(
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
        )
        let sourcePaths = try sources.map { try SourcePath($0.path) }.sorted {
            $0.rawValue < $1.rawValue
        }
        let identity = LifecycleIntroductionObservationIdentity(
            snapshotID: snapshotID,
            provenance: provenance,
            rules: rules.snapshotRules,
            sourcePaths: sourcePaths
        )
        if let observation = identity.matchingObservation(among: reuseCandidates) {
            return HistoricalObservationResult(observation: observation, reused: true)
        }

        let analysis = try RuleEngine().analyze(sources, using: builtInRules)
        let observation = try ObservationSnapshot(
            id: snapshotID,
            provenance: provenance,
            analysis: analysis
        )
        return HistoricalObservationResult(observation: observation, reused: false)
    }

    private func currentRuleDescriptors(
        using rules: [any DebtRule]
    ) throws -> (
        descriptors: [RuleDescriptor],
        snapshotRules: [SnapshotRule]
    ) {
        let descriptors = try RuleEngine().analyze([], using: rules).ruleDescriptors
        let snapshotRules = try descriptors.map { descriptor in
            let snapshotRule = try SnapshotRule(
                identity: descriptor.identity,
                semanticRevision: descriptor.semanticRevision,
                compatibilityDeclarations: descriptor.contract.compatibilityDeclarations,
                configurationCompatibilityDeclarations:
                    descriptor.contract.configurationCompatibilityDeclarations
            )
            return snapshotRule
        }
        return (
            descriptors,
            snapshotRules.sorted {
                if $0.identity.description != $1.identity.description {
                    return $0.identity.description < $1.identity.description
                }
                return $0.semanticRevision.rawValue < $1.semanticRevision.rawValue
            }
        )
    }

}
