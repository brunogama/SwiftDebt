public struct LcovParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> LcovReport {
        var accumulator = LcovAccumulator()
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            accumulator.consume(trimmed(String(rawLine)))
        }
        accumulator.finishRecord()
        return LcovReport(
            records: accumulator.records.sorted {
                normalizedPath($0.sourcePath) < normalizedPath($1.sourcePath)
            })
    }
}

private struct LcovAccumulator {
    var records: [LcovRecord] = []
    var sourcePath: String?
    var functions: [LcovFunctionDefinition] = []
    var functionHits: [LcovFunctionHit] = []
    var lineHits: [LcovLineHit] = []

    mutating func consume(_ line: String) {
        guard !line.isEmpty else { return }
        if line == "end_of_record" {
            finishRecord()
        } else if let path = value(after: "SF:", in: line) {
            finishRecord()
            sourcePath = path
        } else if let definition = functionDefinition(line) {
            functions.append(definition)
        } else if let hit = functionHit(line) {
            functionHits.append(hit)
        } else if let hit = lineHit(line) {
            lineHits.append(hit)
        }
    }

    mutating func finishRecord() {
        guard let sourcePath, !sourcePath.isEmpty else { return }
        records.append(
            LcovRecord(
                sourcePath: sourcePath, functions: functions.sorted(by: functionDefinitionOrder),
                functionHits: functionHits.sorted(by: functionHitOrder),
                lineHits: lineHits.sorted(by: lineHitOrder)))
        self.sourcePath = nil
        functions = []
        functionHits = []
        lineHits = []
    }

    private func functionDefinition(_ line: String) -> LcovFunctionDefinition? {
        guard let parts = pair(after: "FN:", in: line), let lineNumber = Int(parts.first),
            !parts.second.isEmpty
        else { return nil }
        return LcovFunctionDefinition(line: lineNumber, name: parts.second)
    }

    private func functionHit(_ line: String) -> LcovFunctionHit? {
        guard let parts = pair(after: "FNDA:", in: line), let hits = Int(parts.first),
            !parts.second.isEmpty
        else { return nil }
        return LcovFunctionHit(name: parts.second, hits: hits)
    }

    private func lineHit(_ line: String) -> LcovLineHit? {
        guard let raw = value(after: "DA:", in: line) else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2, let lineNumber = Int(parts[0]), let hits = Int(parts[1]) else {
            return nil
        }
        return LcovLineHit(line: lineNumber, hits: hits)
    }

    private func pair(after prefix: String, in line: String) -> (first: String, second: String)? {
        guard let raw = value(after: prefix, in: line), let comma = raw.firstIndex(of: ",") else {
            return nil
        }
        return (String(raw[..<comma]), String(raw[raw.index(after: comma)...]))
    }
}

private func value(after prefix: String, in line: String) -> String? {
    line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
}

private func trimmed(_ value: String) -> String {
    var start = value.startIndex
    var end = value.endIndex
    while start < end, isWhitespace(value[start]) { start = value.index(after: start) }
    while end > start {
        let previous = value.index(before: end)
        guard isWhitespace(value[previous]) else { break }
        end = previous
    }
    return String(value[start..<end])
}

private func isWhitespace(_ character: Character) -> Bool {
    character == " " || character == "\t" || character == "\r" || character == "\n"
}

private func functionDefinitionOrder(_ lhs: LcovFunctionDefinition, _ rhs: LcovFunctionDefinition)
    -> Bool
{
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    return lhs.name < rhs.name
}

private func functionHitOrder(_ lhs: LcovFunctionHit, _ rhs: LcovFunctionHit) -> Bool {
    if lhs.name != rhs.name { return lhs.name < rhs.name }
    return lhs.hits < rhs.hits
}

private func lineHitOrder(_ lhs: LcovLineHit, _ rhs: LcovLineHit) -> Bool {
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    return lhs.hits < rhs.hits
}
