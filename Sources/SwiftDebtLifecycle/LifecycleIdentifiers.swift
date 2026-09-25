import Foundation

public struct SnapshotID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateLifecycleIdentifier(rawValue, kind: "snapshot ID")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        do {
            try self.init(values.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: String(describing: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }
}

public struct AtomicObservationID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateLifecycleIdentifier(rawValue, kind: "atomic observation ID")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        do {
            try self.init(values.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: String(describing: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }
}

public struct DetectionID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateLifecycleIdentifier(rawValue, kind: "detection ID")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        do {
            try self.init(values.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: String(describing: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }
}

public struct FindingID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateLifecycleIdentifier(rawValue, kind: "Finding ID")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        do {
            try self.init(values.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: String(describing: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }
}

public struct LifecycleEventID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateLifecycleIdentifier(rawValue, kind: "lifecycle event ID")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        do {
            try self.init(values.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: String(describing: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }
}

public struct LineageID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) throws {
        try validateLifecycleIdentifier(rawValue, kind: "lineage ID")
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.singleValueContainer()
        do {
            try self.init(values.decode(String.self))
        } catch {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: String(describing: error))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(rawValue)
    }
}

private func validateLifecycleIdentifier(_ value: String, kind: String) throws {
    guard value.utf8.count <= 2_048, hasLifecycleContent(value) else {
        throw LifecycleContractError.invalidIdentifier(kind: kind, value: value)
    }
}
