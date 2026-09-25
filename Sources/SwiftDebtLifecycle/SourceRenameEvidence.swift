import SwiftDebtCore

/// A Git-reported rename between the direct parent and this snapshot.
/// Structural evidence is still required before this can support continuity.
public struct SourceRenameEvidence: Equatable, Sendable {
    public let priorSourcePath: SourcePath
    public let currentSourcePath: SourcePath
    public let similarityPercentage: Int

    package init(
        priorSourcePath: SourcePath,
        currentSourcePath: SourcePath,
        similarityPercentage: Int
    ) throws {
        guard priorSourcePath != currentSourcePath else {
            throw LifecycleContractError.invalidSnapshot("A source rename must change its path.")
        }
        guard (50...100).contains(similarityPercentage) else {
            throw LifecycleContractError.invalidSnapshot(
                "Git rename similarity must satisfy the 50 to 100 percent default detection threshold."
            )
        }
        self.priorSourcePath = priorSourcePath
        self.currentSourcePath = currentSourcePath
        self.similarityPercentage = similarityPercentage
    }
}

extension SourceRenameEvidence: Codable {
    private enum CodingKeys: String, CodingKey {
        case priorSourcePath
        case currentSourcePath
        case similarityPercentage
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                priorSourcePath: SourcePath(values.decode(String.self, forKey: .priorSourcePath)),
                currentSourcePath: SourcePath(values.decode(String.self, forKey: .currentSourcePath)),
                similarityPercentage: values.decode(Int.self, forKey: .similarityPercentage)
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
        try values.encode(currentSourcePath.rawValue, forKey: .currentSourcePath)
        try values.encode(similarityPercentage, forKey: .similarityPercentage)
    }
}

package func sourceRenameOrder(_ lhs: SourceRenameEvidence, _ rhs: SourceRenameEvidence) -> Bool {
    if lhs.priorSourcePath != rhs.priorSourcePath {
        return lhs.priorSourcePath.rawValue < rhs.priorSourcePath.rawValue
    }
    return lhs.currentSourcePath.rawValue < rhs.currentSourcePath.rawValue
}
