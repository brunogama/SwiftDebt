import Foundation

extension LifecycleReadService {
    func renderJSON<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    func renderInventory(_ report: LifecycleInventoryReport) -> String {
        var lines = ["SwiftDebt lifecycle inventory"]
        for finding in report.findings {
            let location = finding.lastKnownLocation
            lines.append(
                "\(finding.id.rawValue) \(finding.lifecycleState.rawValue) \(finding.evidenceState.rawValue) "
                    + "\(finding.rule.identity) \(location.sourcePath.rawValue):\(location.line):\(location.column)"
            )
            lines.append("  First Observation: \(finding.firstObservationSnapshotID.rawValue)")
            if let introduction = finding.introductionConclusion {
                lines.append("  \(renderIntroduction(introduction))")
            }
        }
        for unresolved in report.unresolvedDetections {
            let candidates = unresolved.candidateFindingIDs.map(\.rawValue).joined(separator: ",")
            let reasons = unresolved.reasons.map(\.code).joined(separator: ",")
            lines.append(
                "unresolved \(unresolved.snapshotID.rawValue) \(unresolved.detectionID.rawValue) "
                    + "candidates=\(candidates) reasons=\(reasons)"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func renderExplanation(_ report: FindingExplanationReport) -> String {
        var lines = [
            "Finding \(report.finding.id.rawValue)",
            "State: \(report.finding.lifecycleState.rawValue)",
            "Evidence: \(report.finding.evidenceState.rawValue)",
            "First Observation: \(report.finding.firstObservationSnapshotID.rawValue)",
        ]
        for event in report.finding.events {
            lines.append("\(event.snapshotID.rawValue) \(event.transition.kind.rawValue)")
            lines += reasons(for: event.transition).map { "  \($0.code): \($0.message)" }
        }
        for unresolved in report.unresolvedDetections {
            lines.append("Unresolved Detection \(unresolved.detectionID.rawValue)")
            lines += unresolved.reasons.map { "  \($0.code): \($0.message)" }
        }
        for conclusion in report.introductionConclusions {
            lines.append(renderIntroduction(conclusion))
            lines.append("History budget: \(conclusion.evidence.boundary.maximumRevisions) revisions")
            lines.append(
                "History boundary: head=\(conclusion.evidence.boundary.repositoryHeadRevision.rawValue) "
                    + "state=\(conclusion.evidence.boundary.workingTreeState.rawValue) "
                    + "shallow=\(conclusion.evidence.boundary.isShallow)"
            )
            for revision in conclusion.evidence.revisions {
                let parents = revision.parentRevisions.map(\.rawValue).joined(separator: ",")
                let state = revision.observation == nil ? "unavailable" : "observed"
                lines.append("History revision \(revision.revision.rawValue): \(state) parents=\(parents)")
            }
            if !conclusion.evidence.boundary.frontierRevisions.isEmpty {
                let frontier = conclusion.evidence.boundary.frontierRevisions.map(\.rawValue).joined(separator: ",")
                lines.append("History frontier: \(frontier)")
            }
            lines += conclusion.reasons.map { "  \($0.code): \($0.message)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func renderSnapshot(_ report: SnapshotInspectionReport) -> String {
        let snapshot = report.snapshot
        var lines = [
            "Snapshot \(snapshot.id.rawValue)",
            "Lineage: \(snapshot.provenance.lineage.lineageID.rawValue) #\(snapshot.provenance.lineage.sequence)",
            renderSourceIdentity(snapshot.provenance.sourceIdentity),
            "Scope: \(renderScope(snapshot.provenance.scope))",
            "Configuration: \(snapshot.provenance.configurationFingerprint.value)",
            "Engine: \(snapshot.provenance.engineVersion)",
            "Atomic observations complete: \(snapshot.isAtomicallyComplete)",
            "Repository absence supported: \(snapshot.supportsRepositoryAbsence)",
        ]
        lines += snapshot.provenance.capabilities.map {
            "Capability \($0.name): \(renderCapabilityState($0.state))"
        }
        lines += snapshot.atomicObservations.map {
            "\($0.rule.identity) \($0.sourcePath.rawValue) \($0.outcome.kind.rawValue)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderSourceIdentity(_ identity: SnapshotSourceIdentity) -> String {
        switch identity {
        case .git(let revision, let state, let digest):
            "Git revision: \(revision.rawValue) (\(state.rawValue)) source-sha256=\(digest.value)"
        case .contentDigest(let digest):
            "Source SHA-256: \(digest.value) (Git unavailable)"
        case .unavailable(let reason):
            "Source identity unavailable: \(reason.code): \(reason.message)"
        }
    }

    private func renderScope(_ scope: ObservationScope) -> String {
        switch scope {
        case .repository: "repository"
        case .partial(let reason): "partial (\(reason.code): \(reason.message))"
        }
    }

    private func renderCapabilityState(_ state: SnapshotCapabilityState) -> String {
        switch state {
        case .available: "available"
        case .unavailable(let reason): "unavailable (\(reason.code): \(reason.message))"
        case .ambiguous(let reason): "ambiguous (\(reason.code): \(reason.message))"
        }
    }

    private func reasons(for transition: LifecycleTransition) -> [LifecycleReason] {
        switch transition {
        case .opened: []
        case .observed(let evidence), .reopened(let evidence): evidence.reasons
        case .resolved(let evidence): evidence.reasons
        case .unverified(let reasons): reasons
        case .continuityAmbiguous(let evidence): evidence.reasons
        }
    }

    private func renderIntroduction(_ conclusion: IntroductionConclusion) -> String {
        switch conclusion.kind {
        case .exact:
            return "Introduction: exact \(conclusion.exactRevision?.rawValue ?? "invalid")"
        case .bounded:
            let revision = conclusion.earliestPositiveRevision?.rawValue ?? "unknown"
            return "Introduction: bounded earliest-positive=\(revision)"
        case .unavailable:
            return "Introduction: unavailable"
        }
    }
}
