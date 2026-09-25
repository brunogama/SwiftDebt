public enum LifecycleArtifactSchema {
    public static let currentVersion = 1
    public static let reportKind = "swiftdebt-lifecycle"
}

public struct LineageHead: Codable, Equatable, Sendable {
    public let lineageID: LineageID
    public let snapshotID: SnapshotID
    public let sequence: UInt

    public init(lineageID: LineageID, snapshotID: SnapshotID, sequence: UInt) {
        self.lineageID = lineageID
        self.snapshotID = snapshotID
        self.sequence = sequence
    }
}

public struct UnresolvedDetection: Codable, Equatable, Sendable {
    public let snapshotID: SnapshotID
    public let detectionID: DetectionID
    public let candidateFindingIDs: [FindingID]
    public let reasons: [LifecycleReason]

    public init(
        snapshotID: SnapshotID,
        detectionID: DetectionID,
        candidateFindingIDs: [FindingID],
        reasons: [LifecycleReason]
    ) {
        self.snapshotID = snapshotID
        self.detectionID = detectionID
        self.candidateFindingIDs = candidateFindingIDs.sorted { $0.rawValue < $1.rawValue }
        self.reasons = reasons.sorted(by: lifecycleReasonOrder)
    }
}

public struct LifecycleArtifact: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let generatorVersion: String
    public internal(set) var snapshots: [ObservationSnapshot]
    public internal(set) var findings: [Finding]
    public internal(set) var unresolvedDetections: [UnresolvedDetection]
    public internal(set) var processedSnapshotIDs: [SnapshotID]
    public internal(set) var lineageHeads: [LineageHead]
    public internal(set) var introductionConclusions: [IntroductionConclusion]

    public init(generatorVersion: String) throws {
        guard hasLifecycleContent(generatorVersion) else {
            throw LifecycleContractError.invalidArtifact("Generator version must be nonblank.")
        }
        self.schemaVersion = LifecycleArtifactSchema.currentVersion
        self.reportKind = LifecycleArtifactSchema.reportKind
        self.generatorVersion = generatorVersion
        self.snapshots = []
        self.findings = []
        self.unresolvedDetections = []
        self.processedSnapshotIDs = []
        self.lineageHeads = []
        self.introductionConclusions = []
    }

    init(
        schemaVersion: Int,
        reportKind: String,
        generatorVersion: String,
        snapshots: [ObservationSnapshot],
        findings: [Finding],
        unresolvedDetections: [UnresolvedDetection],
        processedSnapshotIDs: [SnapshotID],
        lineageHeads: [LineageHead],
        introductionConclusions: [IntroductionConclusion]
    ) throws {
        guard schemaVersion == LifecycleArtifactSchema.currentVersion else {
            throw LifecycleContractError.invalidArtifact(
                "Unsupported schema version \(schemaVersion); expected \(LifecycleArtifactSchema.currentVersion)."
            )
        }
        guard reportKind == LifecycleArtifactSchema.reportKind else {
            throw LifecycleContractError.invalidArtifact("Unexpected report kind \(reportKind).")
        }
        guard hasLifecycleContent(generatorVersion) else {
            throw LifecycleContractError.invalidArtifact("Generator version must be nonblank.")
        }
        self.schemaVersion = schemaVersion
        self.reportKind = reportKind
        self.generatorVersion = generatorVersion
        self.snapshots = snapshots.sorted(by: Self.snapshotOrder)
        self.findings = findings.sorted { $0.id.rawValue < $1.id.rawValue }
        self.unresolvedDetections = unresolvedDetections.sorted(by: Self.unresolvedOrder)
        self.processedSnapshotIDs = processedSnapshotIDs.sorted { $0.rawValue < $1.rawValue }
        self.lineageHeads = lineageHeads.sorted { $0.lineageID.rawValue < $1.lineageID.rawValue }
        self.introductionConclusions = introductionConclusions
        try validate()
    }

    public func snapshot(id: SnapshotID) -> ObservationSnapshot? {
        snapshots.first { $0.id == id }
    }

    public func finding(id: FindingID) -> Finding? {
        findings.first { $0.id == id }
    }

    public func detection(id: DetectionID, in snapshotID: SnapshotID) -> ObservedDetection? {
        snapshot(id: snapshotID)?.detection(id: id)
    }

    public func introductionConclusions(for findingID: FindingID) -> [IntroductionConclusion] {
        introductionConclusions.filter { $0.findingID == findingID }
    }

    public func currentIntroductionConclusion(for findingID: FindingID) -> IntroductionConclusion? {
        introductionConclusions(for: findingID).max { lhs, rhs in
            let left = Self.introductionRank(lhs.kind)
            let right = Self.introductionRank(rhs.kind)
            return left == right ? lhs.attempt < rhs.attempt : left < right
        }
    }

    private static func snapshotOrder(_ lhs: ObservationSnapshot, _ rhs: ObservationSnapshot) -> Bool {
        let left = lhs.provenance.lineage
        let right = rhs.provenance.lineage
        if left.lineageID != right.lineageID { return left.lineageID.rawValue < right.lineageID.rawValue }
        if left.sequence != right.sequence { return left.sequence < right.sequence }
        return lhs.id.rawValue < rhs.id.rawValue
    }

    private static func unresolvedOrder(_ lhs: UnresolvedDetection, _ rhs: UnresolvedDetection) -> Bool {
        if lhs.snapshotID != rhs.snapshotID { return lhs.snapshotID.rawValue < rhs.snapshotID.rawValue }
        return lhs.detectionID.rawValue < rhs.detectionID.rawValue
    }

    private static func introductionRank(_ kind: IntroductionConclusionKind) -> Int {
        switch kind {
        case .unavailable: 0
        case .bounded: 1
        case .exact: 2
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reportKind
        case generatorVersion
        case snapshots
        case findings
        case unresolvedDetections
        case processedSnapshotIDs
        case lineageHeads
        case introductionConclusions
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == LifecycleArtifactSchema.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported lifecycle artifact schema version \(schemaVersion)."
            )
        }
        let reportKind = try values.decode(String.self, forKey: .reportKind)
        guard reportKind == LifecycleArtifactSchema.reportKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .reportKind,
                in: values,
                debugDescription: "Unexpected lifecycle report kind \(reportKind)."
            )
        }
        do {
            try self.init(
                schemaVersion: schemaVersion,
                reportKind: reportKind,
                generatorVersion: values.decode(String.self, forKey: .generatorVersion),
                snapshots: values.decode([ObservationSnapshot].self, forKey: .snapshots),
                findings: values.decode([Finding].self, forKey: .findings),
                unresolvedDetections: values.decode([UnresolvedDetection].self, forKey: .unresolvedDetections),
                processedSnapshotIDs: values.decode([SnapshotID].self, forKey: .processedSnapshotIDs),
                lineageHeads: values.decode([LineageHead].self, forKey: .lineageHeads),
                introductionConclusions: values.decodeIfPresent(
                    [IntroductionConclusion].self,
                    forKey: .introductionConclusions
                ) ?? []
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .findings,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }
}
