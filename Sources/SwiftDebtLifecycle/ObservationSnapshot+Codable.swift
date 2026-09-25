import SwiftDebtCore

extension ObservationSnapshot {
    private enum CodingKeys: String, CodingKey {
        case id
        case provenance
        case rules
        case sources
        case atomicObservations
        case detections
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(provenance, forKey: .provenance)
        try values.encode(rules, forKey: .rules)
        try values.encode(sources, forKey: .sources)
        try values.encode(atomicObservations, forKey: .atomicObservations)
        try values.encode(detections, forKey: .detections)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let atomicObservations = try values.decode(
                [AtomicObservation].self,
                forKey: .atomicObservations
            )
            let rules =
                try values.decodeIfPresent([SnapshotRule].self, forKey: .rules)
                ?? Array(Set(atomicObservations.map(\.rule)))
            try self.init(
                id: values.decode(SnapshotID.self, forKey: .id),
                provenance: values.decode(SnapshotProvenance.self, forKey: .provenance),
                rules: rules,
                sources: values.decode([SourceObservation].self, forKey: .sources),
                atomicObservations: atomicObservations,
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
