extension LegacyIntroductionConclusionEvaluator {
    func globalBlockers(
        openingSnapshot: ObservationSnapshot,
        evidence: IntroductionHistoryEvidence
    ) throws -> [LifecycleReason] {
        var reasons: [LifecycleReason] = []
        reasons += evidence.boundary.limitingReasons
        if evidence.boundary.workingTreeState != .clean {
            reasons.append(
                try LifecycleReason(
                    code: "dirty-working-tree",
                    message: "A modified working tree cannot support an exact committed introduction."
                )
            )
        }
        if evidence.boundary.isShallow {
            reasons.append(
                try LifecycleReason(
                    code: "shallow-history",
                    message: "A shallow repository cannot prove that all relevant ancestry was inspected."
                )
            )
        }
        if !evidence.boundary.frontierRevisions.isEmpty {
            reasons.append(
                try LifecycleReason(
                    code: "history-budget-exhausted",
                    message: "The history work budget ended before all relevant parents were inspected."
                )
            )
        }
        if !openingSnapshot.provenance.scope.isCompleteRepository {
            reasons.append(
                try LifecycleReason(
                    code: "opening-scope-incomplete",
                    message: "The First Observation does not have repository scope."
                )
            )
        }
        guard case .git(_, let state, _) = openingSnapshot.provenance.sourceIdentity else {
            reasons.append(
                try LifecycleReason(
                    code: "committed-first-observation-unavailable",
                    message: "The First Observation does not have Git source identity."
                )
            )
            return reasons
        }
        if state != .clean {
            reasons.append(
                try LifecycleReason(
                    code: "dirty-first-observation",
                    message: "The First Observation contains uncommitted source state."
                )
            )
        }
        return reasons
    }

    func validate(_ evidence: IntroductionHistoryEvidence) throws {
        let boundary = evidence.boundary
        guard boundary.maximumRevisions > 0 else {
            throw LifecycleContractError.invalidArtifact("History work budgets must be positive.")
        }
        guard evidence.revisions.count <= boundary.maximumRevisions else {
            throw LifecycleContractError.invalidArtifact("History evidence exceeds its recorded work budget.")
        }
        guard Set(evidence.revisions.map(\.revision)).count == evidence.revisions.count,
            Set(boundary.frontierRevisions).count == boundary.frontierRevisions.count,
            boundary.frontierRevisions
                == boundary.frontierRevisions.sorted(by: { $0.rawValue < $1.rawValue }),
            Set(boundary.limitingReasons).count == boundary.limitingReasons.count,
            boundary.limitingReasons == boundary.limitingReasons.sorted(by: lifecycleReasonOrder)
        else {
            throw LifecycleContractError.invalidArtifact("History revision references must be unique and canonical.")
        }
        let captured = Set(evidence.revisions.map(\.revision))
        guard captured.isDisjoint(with: Set(boundary.frontierRevisions)) else {
            throw LifecycleContractError.invalidArtifact(
                "A history revision cannot be both captured and frontier evidence.")
        }
        if let start = boundary.startingRevision {
            guard evidence.revisions.first?.revision == start else {
                throw LifecycleContractError.invalidArtifact("History evidence must begin at its starting revision.")
            }
        } else if !evidence.revisions.isEmpty || !boundary.frontierRevisions.isEmpty {
            throw LifecycleContractError.invalidArtifact(
                "History without a starting revision cannot contain observations.")
        }

        let known = captured.union(boundary.frontierRevisions)
        for record in evidence.revisions {
            guard Set(record.parentRevisions).count == record.parentRevisions.count,
                record.parentRevisions == record.parentRevisions.sorted(by: { $0.rawValue < $1.rawValue }),
                record.parentRevisions.allSatisfy(known.contains),
                (record.observation == nil) != (record.unavailableReason == nil)
            else {
                throw LifecycleContractError.invalidArtifact(
                    "A historical revision has malformed parent or observation evidence."
                )
            }
            guard let observation = record.observation else { continue }
            guard case .git(let revision, let state, _) = observation.provenance.sourceIdentity,
                revision == record.revision,
                state == .clean,
                observation.provenance.lineage.sequence == 1,
                observation.provenance.lineage.predecessorSnapshotID == nil,
                observation.provenance.lineage.lineageID.rawValue == "history-\(record.revision.rawValue)"
            else {
                throw LifecycleContractError.invalidArtifact(
                    "A historical Observation Snapshot has inconsistent revision provenance."
                )
            }
        }
        try validateTraversal(evidence)
    }

    func validateTraversal(_ evidence: IntroductionHistoryEvidence) throws {
        guard let start = evidence.boundary.startingRevision else { return }
        let records = Dictionary(uniqueKeysWithValues: evidence.revisions.map { ($0.revision, $0) })
        var queue = [start]
        var scheduled: Set<GitRevisionID> = [start]
        var expected: [GitRevisionID] = []
        while expected.count < evidence.revisions.count {
            guard !queue.isEmpty else {
                throw LifecycleContractError.invalidArtifact("Historical observations are disconnected.")
            }
            let revision = queue.removeFirst()
            guard let record = records[revision] else {
                throw LifecycleContractError.invalidArtifact(
                    "Historical observations do not follow canonical breadth-first order."
                )
            }
            expected.append(revision)
            for parent in record.parentRevisions where scheduled.insert(parent).inserted {
                queue.append(parent)
            }
        }
        guard expected == evidence.revisions.map(\.revision),
            Set(queue) == Set(evidence.boundary.frontierRevisions)
        else {
            throw LifecycleContractError.invalidArtifact(
                "Historical observations and frontier do not match the recorded traversal."
            )
        }
    }

}
