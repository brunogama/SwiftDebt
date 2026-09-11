/// Exact, token-normalized, physical-code-line clones. This is not Lizard's algorithm.
/// Rolling hashes only select candidates: each reported match is verified against text.
package struct DuplicateDetector {
    private struct Position {
        let file: Int
        let line: Int
    }
    private struct Diagonal: Hashable {
        let firstFile: Int
        let secondFile: Int
        let displacement: Int
    }

    package struct Result {
        package let blocks: [DuplicateBlock]
        package let uniqueLines: Int
    }

    package func detect(_ files: [ParsedSource], options: AnalysisOptions) throws -> Result {
        let width = options.minimumDuplicateLines
        guard files.contains(where: { $0.lines.count >= width }) else {
            return Result(blocks: [], uniqueLines: 0)
        }
        let base: UInt64 = 1_000_003
        var power: UInt64 = 1
        for _ in 0..<width { power = power &* base }
        var buckets: [UInt64: [Position]] = [:]
        var coveredEnds: [Diagonal: Int] = [:]
        var blocks: Set<DuplicateBlock> = []
        var duplicated: [String: Set<Int>] = [:]
        var comparisons = 0

        func spend() throws {
            comparisons += 1
            if comparisons > options.maximumDuplicateComparisons {
                throw AnalysisFailure.duplicateBudgetExceeded(options.maximumDuplicateComparisons)
            }
        }

        for (fileIndex, file) in files.enumerated() {
            let lines = file.lines
            guard lines.count >= width else { continue }
            var prefix: [UInt64] = [0]
            prefix.reserveCapacity(lines.count + 1)
            for line in lines {
                prefix.append(prefix[prefix.count - 1] &* base &+ stableHash(line.signature))
            }
            for start in 0...(lines.count - width) {
                let hash = prefix[start + width] &- (prefix[start] &* power)
                let here = Position(file: fileIndex, line: start)
                for previous in buckets[hash, default: []] {
                    try spend()
                    let other = files[previous.file]
                    let sameFile = previous.file == fileIndex
                    // Do not report a region as its own overlapping duplicate.
                    if sameFile && start - previous.line < width { continue }
                    // Skip only a seed already inside a verified span. Equal preceding
                    // lines alone do not prove coverage when same-file matches are clipped.
                    let diagonal = Diagonal(
                        firstFile: previous.file, secondFile: fileIndex,
                        displacement: previous.line - start
                    )
                    if let end = coveredEnds[diagonal], start + width <= end { continue }
                    var limit = min(other.lines.count - previous.line, lines.count - start)
                    if sameFile { limit = min(limit, start - previous.line) }
                    var length = 0
                    while length < limit {
                        try spend()
                        guard
                            other.lines[previous.line + length].signature
                                == lines[start + length].signature
                        else { break }
                        length += 1
                    }
                    guard length >= width else { continue }
                    coveredEnds[diagonal] = start + length
                    let first = occurrence(file: other, start: previous.line, count: length)
                    let second = occurrence(file: file, start: start, count: length)
                    blocks.insert(DuplicateBlock(first: first, second: second))
                    for offset in 0..<length {
                        duplicated[other.path, default: []].insert(other.lines[previous.line + offset].number)
                        duplicated[file.path, default: []].insert(lines[start + offset].number)
                    }
                }
                buckets[hash, default: []].append(here)
            }
        }
        return Result(
            blocks: blocks.sorted { lhs, rhs in
                if lhs.first.file != rhs.first.file { return lhs.first.file < rhs.first.file }
                if lhs.first.startLine != rhs.first.startLine { return lhs.first.startLine < rhs.first.startLine }
                if lhs.second.file != rhs.second.file { return lhs.second.file < rhs.second.file }
                if lhs.second.startLine != rhs.second.startLine { return lhs.second.startLine < rhs.second.startLine }
                return lhs.first.codeLines < rhs.first.codeLines
            },
            uniqueLines: duplicated.values.reduce(0) { $0 + $1.count }
        )
    }

    private func occurrence(file: ParsedSource, start: Int, count: Int) -> DuplicateOccurrence {
        DuplicateOccurrence(
            file: file.path, startLine: file.lines[start].number,
            endLine: file.lines[start + count - 1].number, codeLines: count
        )
    }

    private func stableHash(_ value: String) -> UInt64 {
        var result: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 { result = (result ^ UInt64(byte)) &* 1_099_511_628_211 }
        return result
    }
}
