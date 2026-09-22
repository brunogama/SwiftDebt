import Foundation

struct GitCommitRecord: Sendable {
    let sha: String
    let authorToken: String
    let timestamp: Date
    let subject: String
    let paths: [String]
}

func parseCommits(_ output: String) -> [GitCommitRecord] {
    let formatter = ISO8601DateFormatter()
    return output.split(separator: "\u{1e}").compactMap { rawRecord in
        var lines = rawRecord.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }
        let fields = lines.removeFirst().split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 4, let timestamp = formatter.date(from: fields[2]) else { return nil }
        return GitCommitRecord(
            sha: fields[0],
            authorToken: fields[1],
            timestamp: timestamp,
            subject: fields[3],
            paths: lines.filter { !$0.isEmpty }.sorted()
        )
    }
}

func isFixOriented(_ subject: String) -> Bool {
    let keywords = ["fix", "bug", "crash", "defect", "regression", "hotfix", "repair"]
    let tokens = subject.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
    return tokens.contains { keywords.contains($0) }
}
