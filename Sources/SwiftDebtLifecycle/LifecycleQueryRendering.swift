import Foundation

extension LifecycleReadService {
    func renderJSON<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    func renderInventory(_ report: LifecycleInventoryReport) -> String {
        var lines = ["SwiftDebt lifecycle inventory"]
        lines += report.headSnapshotIDs.map { "Graph head: \($0.rawValue)" }
        for finding in report.findings {
            let location = finding.lastKnownLocation
            lines.append(
                "\(finding.id.rawValue) head=\(finding.headSnapshotID.rawValue) "
                    + "\(finding.lifecycleState.rawValue) \(finding.evidenceState.rawValue) "
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
            "First Observation: \(report.finding.firstObservationSnapshotID.rawValue)",
        ]
        for projection in report.projections {
            lines.append("Graph head: \(projection.snapshotID.rawValue)")
            lines.append("State: \(projection.lifecycleState.rawValue)")
            lines.append("Evidence: \(projection.evidenceState.rawValue)")
            for event in projection.finding.events {
                lines.append("\(event.snapshotID.rawValue) \(event.transition.kind.rawValue)")
                lines += reasons(for: event.transition).map { "  \($0.code): \($0.message)" }
                for comparison in event.semanticComparisons {
                    lines += renderSemanticComparison(comparison)
                }
            }
        }
        for unresolved in report.unresolvedDetections {
            lines.append("Unresolved Detection \(unresolved.detectionID.rawValue)")
            let candidates = unresolved.candidateFindingIDs.map(\.rawValue).joined(separator: ", ")
            lines.append("  Candidate Findings: \(candidates)")
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
            for comparison in conclusion.semanticComparisons {
                lines += renderSemanticComparison(comparison)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func renderSnapshot(_ report: SnapshotInspectionReport) -> String {
        let snapshot = report.snapshot
        var lines = [
            "Snapshot \(snapshot.id.rawValue)",
            "Graph parent: \(report.parentSnapshotID?.rawValue ?? "none")",
            "Graph children: \(report.childSnapshotIDs.map(\.rawValue).joined(separator: ","))",
            "Graph head: \(report.isHead)",
            "Legacy lineage: \(snapshot.provenance.lineage.lineageID.rawValue) #\(snapshot.provenance.lineage.sequence)",
            renderSourceIdentity(snapshot.provenance.sourceIdentity),
            "Scope: \(renderScope(snapshot.provenance.scope))",
            "Configuration: \(snapshot.provenance.configurationFingerprint.value)",
            "Engine: \(snapshot.provenance.engineVersion)",
            "Atomic observations complete: \(snapshot.isAtomicallyComplete)",
            "Repository absence supported: \(snapshot.supportsRepositoryAbsence)",
        ]
        if let selection = snapshot.provenance.sourceSelection {
            lines.append(
                "Source selection: \(selection.kind.rawValue) root="
                    + (selection.repositoryRelativeRoot?.rawValue ?? ".")
            )
            lines += selection.excludedPathPrefixes.map {
                "Excluded source prefix: \($0.rawValue)"
            }
        }
        lines += snapshot.provenance.capabilities.map {
            "Capability \($0.name): \(renderCapabilityState($0.state))"
        }
        lines += snapshot.rules.map {
            "Selected rule: \($0.identity) semantic-revision=\($0.semanticRevision.rawValue)"
        }
        lines += snapshot.rules.flatMap { rule in
            rule.compatibilityDeclarations.map { declaration in
                "Semantic compatibility: \(rule.identity) revisions="
                    + "\(declaration.fromRevision.rawValue)->\(rule.semanticRevision.rawValue) "
                    + "claims=\(declaration.supportedClaims.map(\.rawValue).joined(separator: ","))"
            }
        }
        lines += snapshot.provenance.sourceRenames.map {
            "Renamed SourceUnit: \($0.priorSourcePath.rawValue) -> \($0.currentSourcePath.rawValue) "
                + "(\($0.similarityPercentage)%)"
        }
        lines += snapshot.provenance.sourceDeletions.map {
            "Deleted SourceUnit: \($0.priorSourcePath.rawValue)"
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

    private func renderSemanticComparison(_ comparison: SemanticComparisonBasis) -> [String] {
        var lines = [
            "  Semantic comparison: \(comparison.claim.rawValue) revisions="
                + "\(comparison.priorRule.semanticRevision.rawValue)->"
                + "\(comparison.currentRule.semanticRevision.rawValue) "
                + comparison.decision.rawValue,
            "    Snapshots: \(comparison.priorSnapshotID.rawValue) -> "
                + comparison.currentSnapshotID.rawValue,
            "    Configuration: \(comparison.priorConfigurationFingerprint.value) -> "
                + comparison.currentConfigurationFingerprint.value,
            "    Engine: \(comparison.priorEngineVersion) -> \(comparison.currentEngineVersion)",
        ]
        if let declaration = comparison.compatibilityDeclaration {
            lines.append(
                "    Declaration: claims="
                    + declaration.supportedClaims.map(\.rawValue).joined(separator: ",")
                    + " rationale=\(declaration.rationale)"
            )
        }
        return lines
    }
}
