import Foundation

public struct RepositorySyntaxCacheRenderer: Sendable {
    public init() {}

    public func json(_ report: RepositorySyntaxCacheReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
    }
}
