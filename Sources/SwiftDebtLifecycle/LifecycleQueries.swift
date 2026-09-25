import Foundation

public struct FindingSummary: Codable, Equatable, Sendable {
    public let id: FindingID
    public let lineageID: LineageID
    public let rule: SnapshotRule
    public let lifecycleState: FindingLifecycleState
    public let evidenceState: FindingEvidenceState
    public let firstObservationSnapshotID: SnapshotID
    public let lastKnownLocation: SnapshotLocation
}

public struct LifecycleInventoryReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let findings: [FindingSummary]
    public let unresolvedDetections: [UnresolvedDetection]

    public init(artifact: LifecycleArtifact) throws {
        try artifact.validate()
        self.schemaVersion = 1
        self.reportKind = "swiftdebt-lifecycle-inventory"
        self.findings = try artifact.findings.map { finding in
            guard let snapshot = artifact.snapshot(id: finding.firstObservationSnapshotID),
                let detection = snapshot.detection(id: finding.openingDetectionID)
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) has no opening Detection."
                )
            }
            return FindingSummary(
                id: finding.id,
                lineageID: finding.lineageID,
                rule: finding.rule,
                lifecycleState: finding.lifecycleState,
                evidenceState: finding.evidenceState,
                firstObservationSnapshotID: finding.firstObservationSnapshotID,
                lastKnownLocation: detection.location
            )
        }
        self.unresolvedDetections = artifact.unresolvedDetections
    }
}

public struct FindingExplanationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let finding: Finding
    public let supportingSnapshots: [ObservationSnapshot]
    public let unresolvedDetections: [UnresolvedDetection]

    public init(findingID: FindingID, artifact: LifecycleArtifact) throws {
        try artifact.validate()
        guard let finding = artifact.finding(id: findingID) else {
            throw LifecycleContractError.missingFinding(findingID.rawValue)
        }
        let snapshotIDs = Set(finding.events.map(\.snapshotID))
        self.schemaVersion = 1
        self.reportKind = "swiftdebt-lifecycle-finding-explanation"
        self.finding = finding
        self.supportingSnapshots = artifact.snapshots.filter { snapshotIDs.contains($0.id) }
        self.unresolvedDetections = artifact.unresolvedDetections.filter {
            $0.candidateFindingIDs.contains(findingID)
        }
    }
}

public struct SnapshotInspectionReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let snapshot: ObservationSnapshot
    public let affectedFindingIDs: [FindingID]
    public let unresolvedDetections: [UnresolvedDetection]

    public init(snapshotID: SnapshotID, artifact: LifecycleArtifact) throws {
        try artifact.validate()
        guard let snapshot = artifact.snapshot(id: snapshotID) else {
            throw LifecycleContractError.missingSnapshot(snapshotID.rawValue)
        }
        self.schemaVersion = 1
        self.reportKind = "swiftdebt-lifecycle-snapshot-inspection"
        self.snapshot = snapshot
        self.affectedFindingIDs = artifact.findings.compactMap { finding in
            finding.events.contains(where: { $0.snapshotID == snapshotID }) ? finding.id : nil
        }.sorted { $0.rawValue < $1.rawValue }
        self.unresolvedDetections = artifact.unresolvedDetections.filter { $0.snapshotID == snapshotID }
    }
}

public enum LifecycleReadFormat: String, Codable, Sendable {
    case text
    case json
}

public struct LifecycleReadService: Sendable {
    public init() {}

    public func inventory(at url: URL, format: LifecycleReadFormat) throws -> String {
        let report = try LifecycleInventoryReport(artifact: LifecycleArtifactStore(artifactURL: url).load())
        switch format {
        case .json: return try renderJSON(report)
        case .text: return renderInventory(report)
        }
    }

    public func explain(
        findingID: FindingID,
        at url: URL,
        format: LifecycleReadFormat
    ) throws -> String {
        let artifact = try LifecycleArtifactStore(artifactURL: url).load()
        let report = try FindingExplanationReport(findingID: findingID, artifact: artifact)
        switch format {
        case .json: return try renderJSON(report)
        case .text: return renderExplanation(report)
        }
    }

    public func inspect(
        snapshotID: SnapshotID,
        at url: URL,
        format: LifecycleReadFormat
    ) throws -> String {
        let artifact = try LifecycleArtifactStore(artifactURL: url).load()
        let report = try SnapshotInspectionReport(snapshotID: snapshotID, artifact: artifact)
        switch format {
        case .json: return try renderJSON(report)
        case .text: return renderSnapshot(report)
        }
    }

    private func renderJSON<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    private func renderInventory(_ report: LifecycleInventoryReport) -> String {
        var lines = ["SwiftDebt lifecycle inventory"]
        for finding in report.findings {
            let location = finding.lastKnownLocation
            lines.append(
                "\(finding.id.rawValue) \(finding.lifecycleState.rawValue) \(finding.evidenceState.rawValue) "
                    + "\(finding.rule.identity) \(location.sourcePath.rawValue):\(location.line):\(location.column)"
            )
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

    private func renderExplanation(_ report: FindingExplanationReport) -> String {
        var lines = [
            "Finding \(report.finding.id.rawValue)",
            "State: \(report.finding.lifecycleState.rawValue)",
            "Evidence: \(report.finding.evidenceState.rawValue)",
        ]
        for event in report.finding.events {
            lines.append("\(event.snapshotID.rawValue) \(event.transition.kind.rawValue)")
            lines += reasons(for: event.transition).map { "  \($0.code): \($0.message)" }
        }
        for unresolved in report.unresolvedDetections {
            lines.append("Unresolved Detection \(unresolved.detectionID.rawValue)")
            lines += unresolved.reasons.map { "  \($0.code): \($0.message)" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderSnapshot(_ report: SnapshotInspectionReport) -> String {
        let snapshot = report.snapshot
        var lines = [
            "Snapshot \(snapshot.id.rawValue)",
            "Lineage: \(snapshot.provenance.lineage.lineageID.rawValue) #\(snapshot.provenance.lineage.sequence)",
            "Atomic observations complete: \(snapshot.isAtomicallyComplete)",
            "Repository absence supported: \(snapshot.supportsRepositoryAbsence)",
        ]
        lines += snapshot.atomicObservations.map {
            "\($0.rule.identity) \($0.sourcePath.rawValue) \($0.outcome.kind.rawValue)"
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func reasons(for transition: LifecycleTransition) -> [LifecycleReason] {
        switch transition {
        case .opened: []
        case .resolved(let evidence): evidence.reasons
        case .unverified(let reasons): reasons
        case .continuityAmbiguous(let evidence): evidence.reasons
        }
    }
}
