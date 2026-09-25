import Foundation

public struct FindingSummary: Codable, Equatable, Sendable {
    public let id: FindingID
    public let lineageID: LineageID
    public let rule: SnapshotRule
    public let lifecycleState: FindingLifecycleState
    public let evidenceState: FindingEvidenceState
    public let firstObservationSnapshotID: SnapshotID
    public let lastKnownLocation: SnapshotLocation
    public let introductionConclusion: IntroductionConclusion?
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
            let reference = finding.latestDetectionReference
            guard let snapshot = artifact.snapshot(id: reference.snapshotID),
                let detection = snapshot.detection(id: reference.detectionID)
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) has no latest observed Detection."
                )
            }
            return FindingSummary(
                id: finding.id,
                lineageID: finding.lineageID,
                rule: finding.rule,
                lifecycleState: finding.lifecycleState,
                evidenceState: finding.evidenceState,
                firstObservationSnapshotID: finding.firstObservationSnapshotID,
                lastKnownLocation: detection.location,
                introductionConclusion: artifact.currentIntroductionConclusion(for: finding.id)
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
    public let introductionConclusions: [IntroductionConclusion]

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
        self.introductionConclusions = artifact.introductionConclusions(for: findingID)
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
}
