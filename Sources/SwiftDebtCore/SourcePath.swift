public struct SourcePath: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(_ value: String) throws {
        guard !value.isEmpty else { throw SourcePathError.empty }
        guard !value.hasPrefix("/"), !Self.hasWindowsDrivePrefix(value) else {
            throw SourcePathError.absolute(value)
        }
        guard !value.contains("\\") else { throw SourcePathError.nonCanonicalSeparator(value) }
        guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw SourcePathError.controlCharacter
        }

        var components: [Substring] = []
        for component in value.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".":
                continue
            case "..":
                guard !components.isEmpty else { throw SourcePathError.escapesRoot(value) }
                components.removeLast()
            default:
                components.append(component)
            }
        }
        guard !components.isEmpty else { throw SourcePathError.empty }
        self.rawValue = components.joined(separator: "/")
    }

    public var description: String { rawValue }

    private static func hasWindowsDrivePrefix(_ value: String) -> Bool {
        guard value.count >= 2 else { return false }
        let start = value.startIndex
        let next = value.index(after: start)
        return value[start].isASCII && value[start].isLetter && value[next] == ":"
    }
}

public enum SourcePathError: Error, Equatable, Sendable, CustomStringConvertible {
    case empty
    case absolute(String)
    case escapesRoot(String)
    case nonCanonicalSeparator(String)
    case controlCharacter

    public var description: String {
        switch self {
        case .empty:
            "SourcePath must contain at least one relative component."
        case .absolute(let path):
            "SourcePath must be relative: \(path)"
        case .escapesRoot(let path):
            "SourcePath must not escape its root: \(path)"
        case .nonCanonicalSeparator(let path):
            "SourcePath must use forward slashes: \(path)"
        case .controlCharacter:
            "SourcePath must not contain control characters."
        }
    }
}
