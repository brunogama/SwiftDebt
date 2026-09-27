struct OpeningDispositionKey: Hashable {
    let snapshotID: SnapshotID
    let detectionID: DetectionID
}

extension LifecycleArtifact {
    func openingDispositionCounts() -> [OpeningDispositionKey: Int] {
        var counts: [OpeningDispositionKey: Int] = [:]
        for finding in findings {
            guard let first = finding.events.first,
                case .opened(let evidence) = first.transition
            else {
                continue
            }
            let key = OpeningDispositionKey(
                snapshotID: first.snapshotID,
                detectionID: evidence.detectionID
            )
            counts[key, default: 0] += 1
        }
        return counts
    }

    func requireOpening(
        of detection: ObservedDetection,
        snapshotID: SnapshotID,
        counts: [OpeningDispositionKey: Int]
    ) throws {
        let key = OpeningDispositionKey(snapshotID: snapshotID, detectionID: detection.id)
        guard counts[key] == 1 else {
            throw LifecycleContractError.invalidArtifact(
                "Detection \(detection.id) must open exactly one new Finding."
            )
        }
    }
}
