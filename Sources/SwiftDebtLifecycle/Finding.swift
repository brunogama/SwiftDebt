public struct Finding: Codable, Equatable, Sendable {
    public let id: FindingID
    /// The lineage in which the immutable First Observation was recorded.
    /// Snapshot graph projections, rather than this value, determine later state.
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
        try validateEventGraph()
        self.events = try canonicalEvents()
    }

    public var firstObservationSnapshotID: SnapshotID {
        openingEvent.snapshotID
    }

    /// A conservative aggregate retained for source compatibility. Branch-aware
    /// consumers should use `LifecycleArtifact.findingProjection(id:at:)`.
    public var lifecycleState: FindingLifecycleState {
        terminalEvents.contains { state(after: $0.id) == .open } ? .open : .resolved
    }

    /// A conservative aggregate retained for source compatibility. Divergent
    /// evidence is reported as unverified until a graph head is selected.
    public var evidenceState: FindingEvidenceState {
        let states = Set(terminalEvents.map { evidenceState(for: $0) })
        return states.count == 1 ? states.first ?? .unverified : .unverified
    }

    public var openingDetectionID: DetectionID {
        guard case .opened(let evidence) = openingEvent.transition else {
            preconditionFailure("Validated Findings always contain one opened event.")
        }
        return evidence.detectionID
    }

    package var latestDetectionReference: (snapshotID: SnapshotID, detectionID: DetectionID) {
        guard terminalEvents.count == 1, let terminal = terminalEvents.first else {
            preconditionFailure("Select a snapshot graph projection before requesting latest Detection evidence.")
        }
        for event in (try? eventPath(endingAt: terminal.id))?.reversed() ?? [] {
            switch event.transition {
            case .opened(let evidence):
                return (event.snapshotID, evidence.detectionID)
            case .observed(let evidence), .reopened(let evidence):
                return (event.snapshotID, evidence.currentDetection.detectionID)
            case .resolved, .unverified, .continuityAmbiguous:
                continue
            }
        }
        preconditionFailure("Validated Findings always contain observational evidence.")
    }

    package var openingEvent: LifecycleEvent {
        guard let event = events.first(where: { $0.transition.kind == .opened }) else {
            preconditionFailure("Validated Findings always contain one opened event.")
        }
        return event
    }

    package var terminalEvents: [LifecycleEvent] {
        let referenced = Set(events.flatMap(\.basisEventIDs))
        return events.filter { !referenced.contains($0.id) }
    }

    mutating func append(_ event: LifecycleEvent) throws {
        guard !events.contains(where: { $0.id == event.id }) else { return }
        self = try Finding(
            id: id,
            lineageID: lineageID,
            rule: rule,
            events: events + [event]
        )
    }

    package func projected(through terminalEventID: LifecycleEventID) throws -> Finding {
        try Finding(
            id: id,
            lineageID: lineageID,
            rule: rule,
            events: eventPath(endingAt: terminalEventID)
        )
    }

    package func eventPath(endingAt terminalEventID: LifecycleEventID) throws -> [LifecycleEvent] {
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.id, $0) })
        var path: [LifecycleEvent] = []
        var cursor = terminalEventID
        var visited: Set<LifecycleEventID> = []
        while true {
            guard visited.insert(cursor).inserted, let event = byID[cursor] else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(id) has a cyclic or broken event basis."
                )
            }
            path.append(event)
            guard let basis = event.basisEventIDs.first else { break }
            cursor = basis
        }
        let ordered = path.reversed()
        guard ordered.first?.transition.kind == .opened else {
            throw LifecycleContractError.invalidArtifact(
                "Finding \(id) has an event path that does not reach its opening."
            )
        }
        return Array(ordered)
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
