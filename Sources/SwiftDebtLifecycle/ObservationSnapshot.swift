import SwiftDebtCore

public struct ObservationSnapshot: Codable, Equatable, Sendable {
    public let id: SnapshotID
    public let provenance: SnapshotProvenance
    public let sources: [SourceObservation]
    public let atomicObservations: [AtomicObservation]
    public let detections: [ObservedDetection]

    package init(
        id: SnapshotID,
        provenance: SnapshotProvenance,
        sources: [SourceObservation],
        atomicObservations: [AtomicObservation],
        detections: [ObservedDetection]
    ) throws {
        self.id = id
        self.provenance = provenance
        self.sources = sources.sorted { $0.sourcePath.rawValue < $1.sourcePath.rawValue }
        self.atomicObservations = atomicObservations.sorted(by: Self.atomicOrder)
        self.detections = detections.sorted { $0.id.rawValue < $1.id.rawValue }
        try validate()
    }

    public var isAtomicallyComplete: Bool {
        atomicObservations.allSatisfy(\.outcome.isCommitted)
    }

    public var supportsRepositoryAbsence: Bool {
        provenance.scope.isCompleteRepository && isAtomicallyComplete
    }

    public func atomicObservation(id: AtomicObservationID) -> AtomicObservation? {
        atomicObservations.first { $0.id == id }
    }

    public func detection(id: DetectionID) -> ObservedDetection? {
        detections.first { $0.id == id }
    }

    private func validate() throws {
        try provenance.validate()
        guard !sources.isEmpty else {
            throw LifecycleContractError.invalidSnapshot("At least one SourceUnit is required.")
        }
        guard Set(sources.map(\.sourcePath)).count == sources.count else {
            throw LifecycleContractError.invalidSnapshot("SourceUnit paths must be unique.")
        }
        guard !atomicObservations.isEmpty else {
            throw LifecycleContractError.invalidSnapshot("At least one Atomic Observation is required.")
        }
        guard Set(atomicObservations.map(\.id)).count == atomicObservations.count else {
            throw LifecycleContractError.invalidSnapshot("Atomic Observation IDs must be unique.")
        }
        let atomicKeys = atomicObservations.map {
            AtomicObservationKey(rule: $0.rule, sourcePath: $0.sourcePath)
        }
        guard Set(atomicKeys).count == atomicKeys.count else {
            throw LifecycleContractError.invalidSnapshot("Rule and SourceUnit pairs must be unique.")
        }

        let sourcePaths = Set(sources.map(\.sourcePath))
        guard atomicObservations.allSatisfy({ sourcePaths.contains($0.sourcePath) }) else {
            throw LifecycleContractError.invalidSnapshot("Atomic Observations must reference selected SourceUnits.")
        }
        let rules = Set(atomicObservations.map(\.rule))
        let expectedKeys = Set(
            rules.flatMap { rule in
                sourcePaths.map { AtomicObservationKey(rule: rule, sourcePath: $0) }
            }
        )
        guard Set(atomicKeys) == expectedKeys else {
            throw LifecycleContractError.invalidSnapshot(
                "Every selected rule and SourceUnit pair requires an Atomic Observation."
            )
        }

        guard Set(detections.map(\.id)).count == detections.count else {
            throw LifecycleContractError.invalidSnapshot("Detection IDs must be unique.")
        }
        let detectionByID = Dictionary(uniqueKeysWithValues: detections.map { ($0.id, $0) })
        var referencedDetectionIDs: [DetectionID] = []
        for observation in atomicObservations {
            guard case .committed(let detectionIDs) = observation.outcome else { continue }
            guard Set(detectionIDs).count == detectionIDs.count else {
                throw LifecycleContractError.invalidSnapshot(
                    "An Atomic Observation cannot reference a Detection more than once."
                )
            }
            for detectionID in detectionIDs {
                guard let detection = detectionByID[detectionID] else {
                    throw LifecycleContractError.invalidSnapshot(
                        "Atomic Observation \(observation.id) references missing Detection \(detectionID)."
                    )
                }
                guard detection.rule == observation.rule,
                    detection.location.sourcePath == observation.sourcePath
                else {
                    throw LifecycleContractError.invalidSnapshot(
                        "Detection \(detectionID) does not belong to its Atomic Observation."
                    )
                }
                referencedDetectionIDs.append(detectionID)
            }
        }
        guard Set(referencedDetectionIDs) == Set(detections.map(\.id)),
            referencedDetectionIDs.count == detections.count
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Every Detection must belong to exactly one committed Atomic Observation."
            )
        }

        for source in sources {
            let outcomes = atomicObservations.filter { $0.sourcePath == source.sourcePath }.map(\.outcome)
            switch source.parseOutcome {
            case .failed:
                guard
                    outcomes.allSatisfy({ outcome in
                        guard case .notExecuted(let reason) = outcome else { return false }
                        return reason.code == "source-parse-failed"
                    })
                else {
                    throw LifecycleContractError.invalidSnapshot(
                        "Every rule for a parse-failed SourceUnit must be not executed."
                    )
                }
            case .parsed:
                guard !outcomes.contains(where: { $0.kind == .notExecuted }) else {
                    throw LifecycleContractError.invalidSnapshot(
                        "A parsed SourceUnit cannot carry a parse-only not-executed outcome."
                    )
                }
            }
        }
    }

    private static func atomicOrder(_ lhs: AtomicObservation, _ rhs: AtomicObservation) -> Bool {
        if lhs.rule.identity.description != rhs.rule.identity.description {
            return lhs.rule.identity.description < rhs.rule.identity.description
        }
        if lhs.rule.semanticRevision.rawValue != rhs.rule.semanticRevision.rawValue {
            return lhs.rule.semanticRevision.rawValue < rhs.rule.semanticRevision.rawValue
        }
        return lhs.sourcePath.rawValue < rhs.sourcePath.rawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provenance
        case sources
        case atomicObservations
        case detections
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                id: values.decode(SnapshotID.self, forKey: .id),
                provenance: values.decode(SnapshotProvenance.self, forKey: .provenance),
                sources: values.decode([SourceObservation].self, forKey: .sources),
                atomicObservations: values.decode([AtomicObservation].self, forKey: .atomicObservations),
                detections: values.decode([ObservedDetection].self, forKey: .detections)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }
}

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
    }
}
