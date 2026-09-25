import SwiftDebtCore

public struct ObservationSnapshot: Codable, Equatable, Sendable {
    public let id: SnapshotID
    public let provenance: SnapshotProvenance
    public let rules: [SnapshotRule]
    public let sources: [SourceObservation]
    public let atomicObservations: [AtomicObservation]
    public let detections: [ObservedDetection]

    package init(
        id: SnapshotID,
        provenance: SnapshotProvenance,
        rules: [SnapshotRule],
        sources: [SourceObservation],
        atomicObservations: [AtomicObservation],
        detections: [ObservedDetection]
    ) throws {
        self.id = id
        self.provenance = provenance
        self.rules = rules.sorted(by: Self.ruleOrder)
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
        guard !rules.isEmpty else {
            throw LifecycleContractError.invalidSnapshot("At least one rule must be selected.")
        }
        guard Set(rules.map(\.identity)).count == rules.count else {
            throw LifecycleContractError.invalidSnapshot(
                "Selected rules must have unique Rule Identities."
            )
        }
        guard Set(sources.map(\.sourcePath)).count == sources.count else {
            throw LifecycleContractError.invalidSnapshot("SourceUnit paths must be unique.")
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
        if let selection = provenance.sourceSelection {
            let repositoryPaths = Set(sources.map { selection.repositoryPath(for: $0.sourcePath) })
            guard
                provenance.sourceDeletions.allSatisfy({
                    !repositoryPaths.contains($0.priorSourcePath.rawValue)
                })
            else {
                throw LifecycleContractError.invalidSnapshot(
                    "A Git-deleted SourceUnit cannot remain in the selected source set."
                )
            }
        }
        guard atomicObservations.allSatisfy({ sourcePaths.contains($0.sourcePath) }) else {
            throw LifecycleContractError.invalidSnapshot("Atomic Observations must reference selected SourceUnits.")
        }
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

    private static func ruleOrder(_ lhs: SnapshotRule, _ rhs: SnapshotRule) -> Bool {
        if lhs.identity.description != rhs.identity.description {
            return lhs.identity.description < rhs.identity.description
        }
        return lhs.semanticRevision.rawValue < rhs.semanticRevision.rawValue
    }

}
