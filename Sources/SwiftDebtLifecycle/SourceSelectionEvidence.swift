import SwiftDebtCore

public enum SourceSelectionKind: String, Codable, Equatable, Sendable {
    case directory
    case file
    case manifest
}

/// Engine-recorded source selection expressed in repository-relative paths.
public struct SourceSelectionEvidence: Codable, Equatable, Sendable {
    public let kind: SourceSelectionKind
    public let repositoryRelativeRoot: SourcePath?
    public let excludedPathPrefixes: [SourcePath]

    package init(
        kind: SourceSelectionKind,
        repositoryRelativeRoot: SourcePath?,
        excludedPathPrefixes: [SourcePath]
    ) throws {
        let exclusions = excludedPathPrefixes.sorted { $0.rawValue < $1.rawValue }
        guard Set(exclusions).count == exclusions.count else {
            throw LifecycleContractError.invalidSnapshot(
                "Source selection exclusion prefixes must be unique."
            )
        }
        self.kind = kind
        self.repositoryRelativeRoot = repositoryRelativeRoot
        self.excludedPathPrefixes = exclusions
    }

    package func repositoryPath(for selectedPath: SourcePath) -> String {
        guard let repositoryRelativeRoot else { return selectedPath.rawValue }
        return repositoryRelativeRoot.rawValue + "/" + selectedPath.rawValue
    }

    package func explicitlyExcludes(_ repositoryPath: SourcePath) -> Bool {
        excludedPathPrefixes.contains { prefix in
            repositoryPath == prefix
                || repositoryPath.rawValue.hasPrefix(prefix.rawValue + "/")
        }
    }

    package func includes(
        _ repositoryPath: SourcePath,
        selectedRepositoryPaths: Set<String>
    ) -> Bool {
        guard !explicitlyExcludes(repositoryPath) else { return false }
        switch kind {
        case .directory:
            guard let repositoryRelativeRoot else { return true }
            return repositoryPath.rawValue.hasPrefix(repositoryRelativeRoot.rawValue + "/")
        case .file, .manifest:
            return selectedRepositoryPaths.contains(repositoryPath.rawValue)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case repositoryRelativeRoot
        case excludedPathPrefixes
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let root = try values.decodeIfPresent(String.self, forKey: .repositoryRelativeRoot)
            try self.init(
                kind: values.decode(SourceSelectionKind.self, forKey: .kind),
                repositoryRelativeRoot: root.map(SourcePath.init),
                excludedPathPrefixes: values.decode([String].self, forKey: .excludedPathPrefixes)
                    .map(SourcePath.init)
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encodeIfPresent(repositoryRelativeRoot?.rawValue, forKey: .repositoryRelativeRoot)
        try values.encode(excludedPathPrefixes.map(\.rawValue), forKey: .excludedPathPrefixes)
    }
}
