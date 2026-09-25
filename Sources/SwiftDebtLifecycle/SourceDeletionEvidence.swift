import SwiftDebtCore

/// A Git-recorded Swift SourceUnit deletion between the direct parent and this snapshot.
public struct SourceDeletionEvidence: Codable, Equatable, Sendable {
    public let priorSourcePath: SourcePath

    package init(priorSourcePath: SourcePath) throws {
        guard priorSourcePath.rawValue.hasSuffix(".swift") else {
            throw LifecycleContractError.invalidSnapshot(
                "Source deletion evidence must reference a Swift SourceUnit."
            )
        }
        self.priorSourcePath = priorSourcePath
    }

    private enum CodingKeys: String, CodingKey {
        case priorSourcePath
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                priorSourcePath: SourcePath(values.decode(String.self, forKey: .priorSourcePath))
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .priorSourcePath,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(priorSourcePath.rawValue, forKey: .priorSourcePath)
    }
}

package func sourceDeletionOrder(_ lhs: SourceDeletionEvidence, _ rhs: SourceDeletionEvidence) -> Bool {
    lhs.priorSourcePath.rawValue < rhs.priorSourcePath.rawValue
}
