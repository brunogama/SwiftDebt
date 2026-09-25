import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle

public enum LifecycleAnalysisError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidArtifactPath
    case sourceChangedDuringCapture
    case gitInspectionFailed(String)
    case unorderedSnapshot(String)
    case invalidHistoryBudget

    public var description: String {
        switch self {
        case .invalidArtifactPath:
            "The lifecycle artifact path must be nonblank and separate from analysis inputs and outputs."
        case .sourceChangedDuringCapture:
            "Git source state changed while SwiftDebt captured the analyzed SourceUnits; retry the analysis."
        case .gitInspectionFailed(let reason):
            "Unable to inspect Git provenance for lifecycle ingestion: \(reason)"
        case .unorderedSnapshot(let reason):
            "Lifecycle ingestion cannot establish source order: \(reason)"
        case .invalidHistoryBudget:
            "Lifecycle introduction limits must be positive integers."
        }
    }
}

struct LifecycleObservationIngestor: Sendable {
    func ingest(
        analysis: AnalysisSnapshot,
        capture: LifecycleAnalysisCapture,
        engineVersion: String,
        artifactURL: URL
    ) throws -> LifecycleReduction {
        let capability = try SnapshotCapability(name: "syntax-analysis", state: .available)
        let capabilities = [capability]
        let configuration = try LifecycleCanonicalDigest.configuration(
            analysis: analysis,
            capture: capture
        )
        let snapshotID = try LifecycleCanonicalDigest.snapshotID(
            sourceIdentity: capture.sourceIdentity,
            scope: capture.scope,
            configuration: configuration,
            capabilities: capabilities,
            engineVersion: engineVersion,
            sourceSelection: capture.sourceSelection,
            sourceRenames: capture.sourceRenames,
            sourceDeletions: capture.sourceDeletions
        )
        let store = LifecycleArtifactStore(artifactURL: artifactURL, generatorVersion: engineVersion)
        return try store.ingest { artifact in
            let lineage = try lineagePosition(
                snapshotID: snapshotID,
                gitSnapshot: capture.gitSnapshot,
                artifact: artifact
            )
            return try ObservationSnapshot(
                id: snapshotID,
                provenance: SnapshotProvenance(
                    sourceIdentity: capture.sourceIdentity,
                    scope: capture.scope,
                    configurationFingerprint: configuration,
                    capabilities: capabilities,
                    engineVersion: engineVersion,
                    lineage: lineage,
                    sourceSelection: capture.sourceSelection,
                    sourceRenames: capture.sourceRenames,
                    sourceDeletions: capture.sourceDeletions
                ),
                analysis: analysis
            )
        }
    }

    private func lineagePosition(
        snapshotID: SnapshotID,
        gitSnapshot: LifecycleGitSnapshot,
        artifact: LifecycleArtifact?
    ) throws -> LineagePosition {
        if let existing = artifact?.snapshot(id: snapshotID) {
            return existing.provenance.lineage
        }
        guard let artifact, !artifact.snapshots.isEmpty else {
            if case .available(_, _, let state, _, _, _, _) = gitSnapshot, state != .clean {
                throw LifecycleAnalysisError.unorderedSnapshot(
                    "a dirty working tree cannot seed an extendable lifecycle lineage."
                )
            }
            return try LineagePosition(
                lineageID: LineageID("lineage-\(snapshotID.rawValue.dropFirst("snapshot-".count))"),
                sequence: 1
            )
        }

        guard case .available(_, let revision, let state, let parents, _, _, _) = gitSnapshot else {
            throw LifecycleAnalysisError.unorderedSnapshot(
                "a non-Git successor has no engine-validated predecessor relationship."
            )
        }
        guard state == .clean else {
            throw LifecycleAnalysisError.unorderedSnapshot(
                "a dirty working tree cannot establish a lifecycle successor."
            )
        }
        guard !artifact.snapshots.contains(where: { gitRevision(of: $0) == revision }) else {
            throw LifecycleAnalysisError.unorderedSnapshot(
                "the artifact already contains different evidence for Git revision \(revision.rawValue)."
            )
        }
        guard parents.count == 1, let parentRevision = parents.first else {
            let reason =
                parents.isEmpty
                ? "the revision has no parent present in this nonempty artifact."
                : "merge commits require explicit multi-parent lineage support."
            throw LifecycleAnalysisError.unorderedSnapshot(reason)
        }

        let candidates = artifact.lineageHeads.compactMap { head -> LineageHead? in
            guard let snapshot = artifact.snapshot(id: head.snapshotID),
                gitRevision(of: snapshot) == parentRevision,
                gitWorkingTreeState(of: snapshot) == .clean
            else { return nil }
            return head
        }
        guard candidates.count == 1, let predecessor = candidates.first else {
            throw LifecycleAnalysisError.unorderedSnapshot(
                "the direct Git parent is not one unique clean lineage head in the artifact."
            )
        }
        return try LineagePosition(
            lineageID: predecessor.lineageID,
            sequence: predecessor.sequence + 1,
            predecessorSnapshotID: predecessor.snapshotID
        )
    }

    private func gitRevision(of snapshot: ObservationSnapshot) -> GitRevisionID? {
        guard case .git(let revision, _, _) = snapshot.provenance.sourceIdentity else { return nil }
        return revision
    }

    private func gitWorkingTreeState(of snapshot: ObservationSnapshot) -> SourceWorkingTreeState? {
        guard case .git(_, let state, _) = snapshot.provenance.sourceIdentity else { return nil }
        return state
    }
}
