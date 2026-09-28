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
    private struct State {
        var buckets: [UInt64: [Position]] = [:]
        var coveredEnds: [Diagonal: Int] = [:]
        var blocks: Set<DuplicateBlock> = []
        var duplicated: [String: Set<Int>] = [:]
        var comparisons = 0

        mutating func spend(limit: Int) throws {
            comparisons += 1
            if comparisons > limit { throw AnalysisFailure.duplicateBudgetExceeded(limit) }
        }
    }
    private struct ScanContext {
        let files: [ParsedSource]
        let width: Int
        let power: UInt64
        let comparisonLimit: Int
    }
    private struct Candidate {
        let previous: Position
        let fileIndex: Int
        let start: Int
    }
    private struct LineMatch {
        let other: ParsedSource
        let previousLine: Int
        let file: ParsedSource
        let start: Int
        let limit: Int
    }
    private struct DuplicateSpan {
        let first: DuplicateOccurrence
        let second: DuplicateOccurrence
        let other: ParsedSource
        let previousLine: Int
        let file: ParsedSource
        let start: Int
        let count: Int
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
        var state = State()
        let context = ScanContext(
            files: files, width: width, power: power,
            comparisonLimit: options.maximumDuplicateComparisons)
        for fileIndex in files.indices {
            try scan(fileIndex: fileIndex, context: context, state: &state)
        }
        return Result(
            blocks: state.blocks.sorted { lhs, rhs in
                (
                    lhs.first.file, lhs.first.startLine, lhs.second.file, lhs.second.startLine
                ) < (
                    rhs.first.file, rhs.first.startLine, rhs.second.file, rhs.second.startLine
                )
            },
            uniqueLines: state.duplicated.values.reduce(0) { $0 + $1.count }
        )
    }

    private func scan(
        fileIndex: Int, context: ScanContext, state: inout State
    ) throws {
        let file = context.files[fileIndex]
        guard file.lines.count >= context.width else { return }
        let base: UInt64 = 1_000_003
        var prefix: [UInt64] = [0]
        prefix.reserveCapacity(file.lines.count + 1)
        for line in file.lines {
            prefix.append(prefix[prefix.count - 1] &* base &+ stableHash(line.signature))
        }
        for start in 0...(file.lines.count - context.width) {
            let hash = prefix[start + context.width] &- (prefix[start] &* context.power)
            for previous in state.buckets[hash, default: []] {
                try compare(
                    Candidate(previous: previous, fileIndex: fileIndex, start: start),
                    context: context, state: &state)
            }
            state.buckets[hash, default: []].append(Position(file: fileIndex, line: start))
        }
    }

    private func compare(
        _ candidate: Candidate, context: ScanContext, state: inout State
    ) throws {
        try state.spend(limit: context.comparisonLimit)
        let file = context.files[candidate.fileIndex]
        let other = context.files[candidate.previous.file]
        let sameFile = candidate.previous.file == candidate.fileIndex
        if sameFile && candidate.start - candidate.previous.line < context.width { return }
        let diagonal = Diagonal(
            firstFile: candidate.previous.file, secondFile: candidate.fileIndex,
            displacement: candidate.previous.line - candidate.start)
        if let end = state.coveredEnds[diagonal], candidate.start + context.width <= end { return }
        var limit = min(
            other.lines.count - candidate.previous.line, file.lines.count - candidate.start)
        if sameFile { limit = min(limit, candidate.start - candidate.previous.line) }
        let length = try matchingLength(
            LineMatch(
                other: other, previousLine: candidate.previous.line, file: file,
                start: candidate.start, limit: limit),
            comparisonLimit: context.comparisonLimit, state: &state)
        guard length >= context.width else { return }
        state.coveredEnds[diagonal] = candidate.start + length
        let first = occurrence(file: other, start: candidate.previous.line, count: length)
        let second = occurrence(file: file, start: candidate.start, count: length)
        state.blocks.insert(DuplicateBlock(first: first, second: second))
        recordDuplicatedLines(
            DuplicateSpan(
                first: first, second: second, other: other,
                previousLine: candidate.previous.line, file: file,
                start: candidate.start, count: length),
            state: &state)
    }

    private func matchingLength(
        _ match: LineMatch, comparisonLimit: Int, state: inout State
    ) throws -> Int {
        var length = 0
        while length < match.limit {
            try state.spend(limit: comparisonLimit)
            guard
                match.other.lines[match.previousLine + length].signature
                    == match.file.lines[match.start + length].signature
            else { break }
            length += 1
        }
        return length
    }

    private func recordDuplicatedLines(
        _ span: DuplicateSpan, state: inout State
    ) {
        for offset in 0..<span.count {
            state.duplicated[span.first.file, default: []].insert(
                span.other.lines[span.previousLine + offset].number)
            state.duplicated[span.second.file, default: []].insert(
                span.file.lines[span.start + offset].number)
        }
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
