import Foundation

public struct FindingSummary: Codable, Equatable, Sendable {
    public let id: FindingID
    public let headSnapshotID: SnapshotID
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
    public let headSnapshotIDs: [SnapshotID]
    public let findings: [FindingSummary]
    public let unresolvedDetections: [UnresolvedDetection]

    public init(artifact: LifecycleArtifact, headSnapshotID: SnapshotID? = nil) throws {
        try artifact.validate()
        let heads = try selectedHeads(headSnapshotID, artifact: artifact)
        self.schemaVersion = 2
        self.reportKind = "swiftdebt-lifecycle-inventory"
        self.headSnapshotIDs = heads
        self.findings = try heads.flatMap { headID -> [FindingSummary] in
            guard let head = artifact.snapshot(id: headID) else {
                throw LifecycleContractError.missingSnapshot(headID.rawValue)
            }
            return try artifact.findingProjections(at: headID).map { projection in
                let finding = projection.finding
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
                    headSnapshotID: headID,
                    lineageID: head.provenance.lineage.lineageID,
                    rule: finding.rule,
                    lifecycleState: finding.lifecycleState,
                    evidenceState: finding.evidenceState,
                    firstObservationSnapshotID: finding.firstObservationSnapshotID,
                    lastKnownLocation: detection.location,
                    introductionConclusion: artifact.currentIntroductionConclusion(for: finding.id)
                )
            }
        }.sorted(by: Self.summaryOrder)
        let selectedSnapshotIDs = try snapshotIDs(on: heads, artifact: artifact)
        self.unresolvedDetections = artifact.unresolvedDetections.filter {
            selectedSnapshotIDs.contains($0.snapshotID)
        }
    }

    private static func summaryOrder(_ lhs: FindingSummary, _ rhs: FindingSummary) -> Bool {
        if lhs.headSnapshotID != rhs.headSnapshotID {
            return lhs.headSnapshotID.rawValue < rhs.headSnapshotID.rawValue
        }
        return lhs.id.rawValue < rhs.id.rawValue
    }
}

public struct FindingExplanationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let finding: Finding
    public let projections: [FindingProjection]
    public let supportingSnapshots: [ObservationSnapshot]
    public let unresolvedDetections: [UnresolvedDetection]
    public let introductionConclusions: [IntroductionConclusion]

    public init(
        findingID: FindingID,
        artifact: LifecycleArtifact,
        headSnapshotID: SnapshotID? = nil
    ) throws {
        try artifact.validate()
        guard let finding = artifact.finding(id: findingID) else {
            throw LifecycleContractError.missingFinding(findingID.rawValue)
        }
        let heads = try selectedHeads(headSnapshotID, artifact: artifact)
        let projections = try heads.compactMap { try artifact.findingProjection(finding, at: $0) }
        if let headSnapshotID, projections.isEmpty {
            throw LifecycleContractError.missingFinding(
                "\(findingID.rawValue) at snapshot \(headSnapshotID.rawValue)"
            )
        }
        let supportingSnapshotIDs = Set(projections.flatMap { $0.finding.events.map(\.snapshotID) })
        let selectedSnapshotIDs = try snapshotIDs(on: projections.map(\.snapshotID), artifact: artifact)
        self.schemaVersion = 2
        self.reportKind = "swiftdebt-lifecycle-finding-explanation"
        self.finding = headSnapshotID == nil ? finding : projections[0].finding
        self.projections = projections.sorted { $0.snapshotID.rawValue < $1.snapshotID.rawValue }
        self.supportingSnapshots = artifact.snapshots.filter { supportingSnapshotIDs.contains($0.id) }
        self.unresolvedDetections = artifact.unresolvedDetections.filter {
            selectedSnapshotIDs.contains($0.snapshotID) && $0.candidateFindingIDs.contains(findingID)
        }
        self.introductionConclusions = artifact.introductionConclusions(for: findingID)
    }
}

public struct SnapshotInspectionReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let snapshot: ObservationSnapshot
    public let parentSnapshotID: SnapshotID?
    public let childSnapshotIDs: [SnapshotID]
    public let isHead: Bool
    public let affectedFindingIDs: [FindingID]
    public let unresolvedDetections: [UnresolvedDetection]

    public init(snapshotID: SnapshotID, artifact: LifecycleArtifact) throws {
        try artifact.validate()
        guard let snapshot = artifact.snapshot(id: snapshotID) else {
            throw LifecycleContractError.missingSnapshot(snapshotID.rawValue)
        }
        self.schemaVersion = 2
        self.reportKind = "swiftdebt-lifecycle-snapshot-inspection"
        self.snapshot = snapshot
        self.parentSnapshotID = artifact.parentSnapshotID(of: snapshotID)
        self.childSnapshotIDs = artifact.childSnapshotIDs(of: snapshotID)
        self.isHead = artifact.headSnapshotIDs.contains(snapshotID)
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

    public func inventory(
        at url: URL,
        headSnapshotID: SnapshotID? = nil,
        format: LifecycleReadFormat
    ) throws -> String {
        let report = try LifecycleInventoryReport(
            artifact: LifecycleArtifactStore(artifactURL: url).load(),
            headSnapshotID: headSnapshotID
        )
        switch format {
        case .json: return try renderJSON(report)
        case .text: return renderInventory(report)
        }
    }

    public func explain(
        findingID: FindingID,
        at url: URL,
        headSnapshotID: SnapshotID? = nil,
        format: LifecycleReadFormat
    ) throws -> String {
        let artifact = try LifecycleArtifactStore(artifactURL: url).load()
        let report = try FindingExplanationReport(
            findingID: findingID,
            artifact: artifact,
            headSnapshotID: headSnapshotID
        )
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

private func selectedHeads(
    _ requested: SnapshotID?,
    artifact: LifecycleArtifact
) throws -> [SnapshotID] {
    guard let requested else { return artifact.headSnapshotIDs }
    guard artifact.headSnapshotIDs.contains(requested) else {
        throw LifecycleContractError.invalidArtifact(
            "Snapshot \(requested) is not a current graph head."
        )
    }
    return [requested]
}

private func snapshotIDs(
    on heads: [SnapshotID],
    artifact: LifecycleArtifact
) throws -> Set<SnapshotID> {
    try Set(heads.flatMap { try artifact.snapshotPath(through: $0).map(\.id) })
}
