import SwiftDebtCore

public enum SourceParseOutcome: Equatable, Sendable {
    case parsed
    case failed([AnalysisDiagnostic])
}

extension SourceParseOutcome: Codable {
    private enum Kind: String, Codable {
        case parsed
        case failed
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case diagnostics
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
        case .parsed:
            guard !values.contains(.diagnostics) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .diagnostics,
                    in: values,
                    debugDescription: "A parsed source cannot carry parse diagnostics."
                )
            }
            self = .parsed
        case .failed:
            let diagnostics = try values.decode([AnalysisDiagnostic].self, forKey: .diagnostics)
            guard !diagnostics.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .diagnostics,
                    in: values,
                    debugDescription: "A source parse failure requires at least one diagnostic."
                )
            }
            self = .failed(diagnostics)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .parsed:
            try values.encode(Kind.parsed, forKey: .kind)
        case .failed(let diagnostics):
            try values.encode(Kind.failed, forKey: .kind)
            try values.encode(diagnostics, forKey: .diagnostics)
        }
    }
}

public struct SourceObservation: Equatable, Sendable {
    public let sourcePath: SourcePath
    public let parseOutcome: SourceParseOutcome

    public init(sourcePath: SourcePath, parseOutcome: SourceParseOutcome) {
        self.sourcePath = sourcePath
        self.parseOutcome = parseOutcome
    }
}

extension SourceObservation: Codable {
    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case parseOutcome
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            self.init(
                sourcePath: try SourcePath(values.decode(String.self, forKey: .sourcePath)),
                parseOutcome: try values.decode(SourceParseOutcome.self, forKey: .parseOutcome)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .sourcePath,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sourcePath.rawValue, forKey: .sourcePath)
        try values.encode(parseOutcome, forKey: .parseOutcome)
    }
}

public enum AtomicObservationOutcome: Equatable, Sendable {
    case committed([DetectionID])
    case unsupported(LifecycleReason)
    case failed(LifecycleReason)
    case excluded(LifecycleReason)
    case notExecuted(LifecycleReason)

    public enum Kind: String, Codable, Sendable {
        case committed
        case unsupported
        case failed
        case excluded
        case notExecuted = "not-executed"
    }

    public var kind: Kind {
        switch self {
        case .committed: .committed
        case .unsupported: .unsupported
        case .failed: .failed
        case .excluded: .excluded
        case .notExecuted: .notExecuted
        }
    }

    public var isCommitted: Bool {
        if case .committed = self { return true }
        return false
    }

    public var provesAbsence: Bool {
        guard case .committed(let detectionIDs) = self else { return false }
        return detectionIDs.isEmpty
    }
}

extension AtomicObservationOutcome: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case detectionIDs
        case reason
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(Kind.self, forKey: .kind)
        switch kind {
        case .committed:
            guard !values.contains(.reason) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .reason,
                    in: values,
                    debugDescription: "A committed Atomic Observation cannot carry a failure reason."
                )
            }
            self = .committed(try values.decode([DetectionID].self, forKey: .detectionIDs))
        case .unsupported, .failed, .excluded, .notExecuted:
            guard !values.contains(.detectionIDs) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .detectionIDs,
                    in: values,
                    debugDescription: "A non-committed Atomic Observation cannot carry Detections."
                )
            }
            let reason = try values.decode(LifecycleReason.self, forKey: .reason)
            switch kind {
            case .unsupported: self = .unsupported(reason)
            case .failed: self = .failed(reason)
            case .excluded: self = .excluded(reason)
            case .notExecuted: self = .notExecuted(reason)
            case .committed: preconditionFailure("Handled above")
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        switch self {
        case .committed(let detectionIDs):
            try values.encode(detectionIDs, forKey: .detectionIDs)
        case .unsupported(let reason), .failed(let reason), .excluded(let reason), .notExecuted(let reason):
            try values.encode(reason, forKey: .reason)
        }
    }
}
