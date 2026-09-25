import SwiftDebtCore

struct ResolutionRelocationAssessment {
    let blockers: [LifecycleReason]
    let proofReasons: [LifecycleReason]
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
        let deletion = snapshot.provenance.sourceDeletions.first {
            $0.priorSourcePath == priorPath
        }
        let rename = snapshot.provenance.sourceRenames.first {
            $0.priorSourcePath == priorPath
        }
        let sourceChangeReason = try sourceChangeReason(
            deletion: deletion,
            rename: rename
        )

        guard !snapshot.provenance.scope.isCompleteRepository else {
            guard let sourceChangeReason else {
                return ResolutionRelocationAssessment(blockers: [], proofReasons: [])
            }
            return ResolutionRelocationAssessment(
                blockers: [],
                proofReasons: [
                    sourceChangeReason,
                    try LifecycleReason(
                        code: "complete-relocation-coverage",
                        message: "Repository scope covered every eligible successor SourceUnit after "
                            + "\(priorPath.rawValue) changed location or was deleted."
                    ),
                ]
            )
        }

        var blockers: [LifecycleReason] = []
        if let sourceChangeReason {
            blockers.append(sourceChangeReason)
        } else if snapshot.provenance.sourceSelection?.explicitlyExcludes(priorPath) == true {
            blockers.append(
                try LifecycleReason(
                    code: "prior-source-out-of-scope",
                    message: "The engine-recorded source selection explicitly excluded the prior SourceUnit "
                        + "\(priorPath.rawValue)."
                )
            )
        } else if let selection = snapshot.provenance.sourceSelection,
            !selection.includes(
                priorPath,
                selectedRepositoryPaths: selectedRepositoryPaths(in: snapshot)
            )
        {
            blockers.append(
                try LifecycleReason(
                    code: "prior-source-out-of-scope",
                    message: "The prior SourceUnit \(priorPath.rawValue) is outside the current selected scope."
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

    private func sourceChangeReason(
        deletion: SourceDeletionEvidence?,
        rename: SourceRenameEvidence?
    ) throws -> LifecycleReason? {
        if let deletion {
            return try LifecycleReason(
                code: "source-deleted",
                message: "Git recorded deletion of prior SourceUnit \(deletion.priorSourcePath.rawValue) "
                    + "on the direct parent edge."
            )
        }
        if let rename {
            return try LifecycleReason(
                code: "source-relocated",
                message: "Git recorded relocation of prior SourceUnit \(rename.priorSourcePath.rawValue) to "
                    + "\(rename.currentSourcePath.rawValue) on the direct parent edge."
            )
        }
        return nil
    }
}
