extension Finding {
    func validateEventGraph() throws {
        guard !events.isEmpty else {
            throw LifecycleContractError.invalidArtifact("Finding \(id) requires an opened event.")
        }
        guard Set(events.map(\.id)).count == events.count else {
            throw LifecycleContractError.invalidArtifact("Finding \(id) has duplicate event IDs.")
        }
        let openings = events.filter { $0.transition.kind == .opened }
        guard openings.count == 1, openings[0].basisEventIDs.isEmpty else {
            throw LifecycleContractError.invalidArtifact("Finding \(id) must have one root opened event.")
        }
        let knownIDs = Set(events.map(\.id))
        for event in events where event.transition.kind != .opened {
            guard event.basisEventIDs.count == 1,
                event.basisEventIDs[0] != event.id,
                knownIDs.contains(event.basisEventIDs[0])
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(id) events require one valid predecessor event."
                )
            }
        }
        for event in events {
            let path = try eventPath(endingAt: event.id)
            guard path.first?.id == openings[0].id else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(id) contains an event disconnected from its opening."
                )
            }
            try validateTransitions(path)
        }
    }

    func validateTransitions(_ path: [LifecycleEvent]) throws {
        var state = FindingLifecycleState.open
        for event in path.dropFirst() {
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

    func canonicalEvents() throws -> [LifecycleEvent] {
        var depthByID: [LifecycleEventID: Int] = [:]
        for event in events {
            depthByID[event.id] = try eventPath(endingAt: event.id).count
        }
        return events.sorted { lhs, rhs in
            let leftDepth = depthByID[lhs.id] ?? 0
            let rightDepth = depthByID[rhs.id] ?? 0
            if leftDepth != rightDepth { return leftDepth < rightDepth }
            if lhs.snapshotID != rhs.snapshotID {
                return lhs.snapshotID.rawValue < rhs.snapshotID.rawValue
            }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }

    func state(after eventID: LifecycleEventID) -> FindingLifecycleState {
        guard let path = try? eventPath(endingAt: eventID) else { return .open }
        return path.reduce(.open) { state, event in
            switch event.transition {
            case .resolved: .resolved
            case .reopened: .open
            case .opened, .observed, .unverified, .continuityAmbiguous: state
            }
        }
    }

    func evidenceState(for event: LifecycleEvent) -> FindingEvidenceState {
        switch event.transition {
        case .opened, .observed, .reopened: .observed
        case .resolved: .verifiedAbsent
        case .unverified: .unverified
        case .continuityAmbiguous: .continuityAmbiguous
        }
    }
}
