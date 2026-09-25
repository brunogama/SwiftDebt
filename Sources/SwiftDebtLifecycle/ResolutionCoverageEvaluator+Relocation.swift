import SwiftDebtCore

struct ResolutionRelocationAssessment {
    let blockers: [LifecycleReason]
    let proofReasons: [LifecycleReason]
}

private struct ResolutionSourceTrace {
    let currentPath: SourcePath
    let isDeleted: Bool
    let reasons: [LifecycleReason]
}

extension ResolutionCoverageEvaluator {
    func assessRelocation(
        finding: Finding,
        snapshot: ObservationSnapshot,
        artifact: LifecycleArtifact
    ) throws -> ResolutionRelocationAssessment {
        let reference = finding.latestDetectionReference
        guard let priorSnapshot = artifact.snapshot(id: reference.snapshotID),
            let priorDetection = priorSnapshot.detection(id: reference.detectionID)
        else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(finding.id) has no latest Detection evidence."
            )
        }
        let priorPath = try repositoryPath(
            for: priorDetection.location.sourcePath,
            selection: priorSnapshot.provenance.sourceSelection
        )
        let trace = try sourceTrace(
            from: priorPath,
            after: priorSnapshot,
            through: snapshot,
            artifact: artifact
        )

        guard !snapshot.provenance.scope.isCompleteRepository else {
            guard !trace.reasons.isEmpty else {
                return ResolutionRelocationAssessment(blockers: [], proofReasons: [])
            }
            return ResolutionRelocationAssessment(
                blockers: [],
                proofReasons: trace.reasons + [
                    try LifecycleReason(
                        code: "complete-relocation-coverage",
                        message: "Repository scope covered every eligible successor SourceUnit after "
                            + "\(priorPath.rawValue) changed location or was deleted."
                    )
                ]
            )
        }

        var blockers = trace.reasons
        if !trace.isDeleted,
            snapshot.provenance.sourceSelection?.explicitlyExcludes(trace.currentPath) == true
        {
            blockers.append(
                try LifecycleReason(
                    code: "prior-source-out-of-scope",
                    message: "The engine-recorded source selection explicitly excluded the prior SourceUnit "
                        + "\(trace.currentPath.rawValue)."
                )
            )
        } else if !trace.isDeleted,
            let selection = snapshot.provenance.sourceSelection,
            !selection.includes(
                trace.currentPath,
                selectedRepositoryPaths: selectedRepositoryPaths(in: snapshot)
            )
        {
            blockers.append(
                try LifecycleReason(
                    code: "prior-source-out-of-scope",
                    message: "The prior SourceUnit \(trace.currentPath.rawValue) is outside the current selected scope."
                )
            )
        }
        blockers.append(
            try LifecycleReason(
                code: "relocation-coverage-incomplete",
                message: "Partial source selection did not cover the complete eligible successor search space."
            )
        )
        return ResolutionRelocationAssessment(blockers: blockers, proofReasons: [])
    }

    private func sourceTrace(
        from priorPath: SourcePath,
        after priorSnapshot: ObservationSnapshot,
        through currentSnapshot: ObservationSnapshot,
        artifact: LifecycleArtifact
    ) throws -> ResolutionSourceTrace {
        let successors = try lineageSuccessors(
            after: priorSnapshot,
            through: currentSnapshot,
            artifact: artifact
        )
        var currentPath = priorPath
        var renameEdges: [(SnapshotID, SourceRenameEvidence)] = []
        var deletionEdge: (SnapshotID, SourceDeletionEvidence)?
        for successor in successors {
            if let deletion = successor.provenance.sourceDeletions.first(where: {
                $0.priorSourcePath == currentPath
            }) {
                deletionEdge = (successor.id, deletion)
                break
            }
            if let rename = successor.provenance.sourceRenames.first(where: {
                $0.priorSourcePath == currentPath
            }) {
                renameEdges.append((successor.id, rename))
                currentPath = rename.currentSourcePath
            }
        }

        var reasons: [LifecycleReason] = []
        if !renameEdges.isEmpty {
            let path = ([priorPath.rawValue] + renameEdges.map { $0.1.currentSourcePath.rawValue })
                .joined(separator: " -> ")
            let snapshots = renameEdges.map { $0.0.rawValue }.joined(separator: ", ")
            reasons.append(
                try LifecycleReason(
                    code: "source-relocated",
                    message: "Git recorded SourceUnit relocation \(path) on direct-parent edges "
                        + "represented by snapshots \(snapshots)."
                )
            )
        }
        if let deletionEdge {
            reasons.append(
                try LifecycleReason(
                    code: "source-deleted",
                    message: "Git recorded deletion of prior SourceUnit "
                        + "\(deletionEdge.1.priorSourcePath.rawValue) on the direct-parent edge represented by "
                        + "snapshot \(deletionEdge.0.rawValue)."
                )
            )
        }
        return ResolutionSourceTrace(
            currentPath: currentPath,
            isDeleted: deletionEdge != nil,
            reasons: reasons
        )
    }

    private func lineageSuccessors(
        after priorSnapshot: ObservationSnapshot,
        through currentSnapshot: ObservationSnapshot,
        artifact: LifecycleArtifact
    ) throws -> [ObservationSnapshot] {
        var reversed: [ObservationSnapshot] = []
        var cursor = currentSnapshot
        var visited: Set<SnapshotID> = []
        while cursor.id != priorSnapshot.id {
            guard visited.insert(cursor.id).inserted,
                cursor.provenance.lineage.lineageID == priorSnapshot.provenance.lineage.lineageID,
                let predecessorID = cursor.provenance.lineage.predecessorSnapshotID,
                let predecessor = artifact.snapshot(id: predecessorID)
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Resolution evidence does not form one ordered lineage from the latest Detection."
                )
            }
            reversed.append(cursor)
            cursor = predecessor
        }
        return reversed.reversed()
    }

    private func selectedRepositoryPaths(in snapshot: ObservationSnapshot) -> Set<String> {
        guard let selection = snapshot.provenance.sourceSelection else { return [] }
        return Set(snapshot.sources.map { selection.repositoryPath(for: $0.sourcePath) })
    }

    private func repositoryPath(
        for selectedPath: SourcePath,
        selection: SourceSelectionEvidence?
    ) throws -> SourcePath {
        guard let selection else { return selectedPath }
        return try SourcePath(selection.repositoryPath(for: selectedPath))
    }
}
