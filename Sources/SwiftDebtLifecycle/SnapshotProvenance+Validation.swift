extension SnapshotProvenance {
    func validate() throws {
        guard hasLifecycleContent(engineVersion) else {
            throw LifecycleContractError.invalidSnapshot("Engine version must be nonblank.")
        }
        guard lineage.sequence > 0,
            (lineage.sequence == 1) == (lineage.predecessorSnapshotID == nil)
        else {
            throw LifecycleContractError.invalidSnapshot("Invalid lineage position.")
        }
        guard Set(capabilities.map(\.name)).count == capabilities.count,
            capabilities == capabilities.sorted(by: { $0.name < $1.name }),
            capabilities.allSatisfy({ hasLifecycleContent($0.name) })
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Capability names must be nonblank, unique, and canonically ordered."
            )
        }
        try validateSourceSelection()
        try validateSourceChanges()
    }

    private func validateSourceSelection() throws {
        guard let sourceSelection else { return }
        guard case .git = sourceIdentity else {
            throw LifecycleContractError.invalidSnapshot(
                "Repository-relative source selection requires Git source identity."
            )
        }
        guard scope.isCompleteRepository else { return }
        guard sourceSelection.kind == .directory,
            sourceSelection.repositoryRelativeRoot == nil,
            sourceSelection.excludedPathPrefixes.isEmpty
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Repository scope requires an unexcluded repository-root directory selection."
            )
        }
    }

    private func validateSourceChanges() throws {
        guard sourceRenames == sourceRenames.sorted(by: sourceRenameOrder),
            Set(sourceRenames.map(\.priorSourcePath)).count == sourceRenames.count,
            Set(sourceRenames.map(\.currentSourcePath)).count == sourceRenames.count
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Source rename evidence must be unique and canonically ordered."
            )
        }
        guard sourceDeletions == sourceDeletions.sorted(by: sourceDeletionOrder),
            Set(sourceDeletions.map(\.priorSourcePath)).count == sourceDeletions.count
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Source deletion evidence must be unique and canonically ordered."
            )
        }
        guard
            Set(sourceRenames.map(\.priorSourcePath)).isDisjoint(
                with: Set(sourceDeletions.map(\.priorSourcePath))
            )
        else {
            throw LifecycleContractError.invalidSnapshot(
                "A prior SourceUnit cannot be both renamed and deleted by one Git edge."
            )
        }
        if !sourceRenames.isEmpty || !sourceDeletions.isEmpty {
            guard case .git = sourceIdentity else {
                throw LifecycleContractError.invalidSnapshot(
                    "Source rename and deletion evidence require Git source identity."
                )
            }
        }
    }
}
