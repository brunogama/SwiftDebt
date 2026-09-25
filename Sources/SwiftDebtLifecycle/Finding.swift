public struct Finding: Codable, Equatable, Sendable {
    public let id: FindingID
    public let lineageID: LineageID
    public let rule: SnapshotRule
    public private(set) var events: [LifecycleEvent]

    init(
        id: FindingID,
        lineageID: LineageID,
        rule: SnapshotRule,
        events: [LifecycleEvent]
    ) throws {
        self.id = id
        self.lineageID = lineageID
        self.rule = rule
        self.events = events
        try validateEventSequence()
    }

    public var firstObservationSnapshotID: SnapshotID {
        events[0].snapshotID
    }

    public var lifecycleState: FindingLifecycleState {
        events.reduce(.open) { state, event in
            if case .resolved = event.transition { return .resolved }
            if case .reopened = event.transition { return .open }
            return state
        }
    }

    public var evidenceState: FindingEvidenceState {
        guard let event = events.last else { return .unverified }
        switch event.transition {
        case .opened, .observed, .reopened: return .observed
        case .resolved: return .verifiedAbsent
        case .unverified: return .unverified
        case .continuityAmbiguous: return .continuityAmbiguous
        }
    }

    public var openingDetectionID: DetectionID {
        guard case .opened(let evidence) = events[0].transition else {
            preconditionFailure("Validated Findings always start with an opened event.")
        }
        return evidence.detectionID
    }

    package var latestDetectionReference: (snapshotID: SnapshotID, detectionID: DetectionID) {
        for event in events.reversed() {
            switch event.transition {
            case .opened(let evidence):
                return (event.snapshotID, evidence.detectionID)
            case .observed(let evidence), .reopened(let evidence):
                return (event.snapshotID, evidence.currentDetection.detectionID)
            case .resolved, .unverified, .continuityAmbiguous:
                continue
            }
        }
        preconditionFailure("Validated Findings always contain an observational event.")
    }

    mutating func append(_ event: LifecycleEvent) throws {
        guard !events.contains(where: { $0.id == event.id }) else { return }
        let next = try Finding(
            id: id,
            lineageID: lineageID,
            rule: rule,
            events: events + [event]
        )
        self = next
    }

    private func validateEventSequence() throws {
        guard let first = events.first, case .opened = first.transition else {
            throw LifecycleContractError.invalidArtifact("Finding \(id) must start with an opened event.")
        }
        guard Set(events.map(\.id)).count == events.count else {
            throw LifecycleContractError.invalidArtifact("Finding \(id) has duplicate event IDs.")
        }
        var state = FindingLifecycleState.open
        for event in events.dropFirst() {
            switch event.transition {
            case .opened:
                throw LifecycleContractError.invalidArtifact("Finding \(id) has more than one opened event.")
            case .observed:
                guard state == .open else {
                    throw LifecycleContractError.invalidArtifact("Finding \(id) is observed while resolved.")
                }
            case .resolved:
                guard state == .open else {
                    throw LifecycleContractError.invalidArtifact("Finding \(id) resolves more than once.")
                }
                state = .resolved
            case .reopened:
                guard state == .resolved else {
                    throw LifecycleContractError.invalidArtifact("Finding \(id) reopens while already open.")
                }
                state = .open
            case .unverified, .continuityAmbiguous:
                guard state == .open else {
                    throw LifecycleContractError.invalidArtifact(
                        "Finding \(id) cannot add uncertain evidence after verified resolution."
                    )
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case lineageID
        case rule
        case events
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: values.decode(FindingID.self, forKey: .id),
                lineageID: values.decode(LineageID.self, forKey: .lineageID),
                rule: values.decode(SnapshotRule.self, forKey: .rule),
                events: values.decode([LifecycleEvent].self, forKey: .events)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .events,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }
}
