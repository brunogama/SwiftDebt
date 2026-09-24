public struct LcovParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> LcovReport {
        var records: [LcovRecord] = []
        var sourcePath: String?
        var functions: [LcovFunctionDefinition] = []
        var functionHits: [LcovFunctionHit] = []
        var lineHits: [LcovLineHit] = []

        func finishRecord() {
            guard let path = sourcePath, !path.isEmpty else { return }
            records.append(
                LcovRecord(
                    sourcePath: path,
                    functions: functions.sorted(by: functionDefinitionOrder),
                    functionHits: functionHits.sorted(by: functionHitOrder),
                    lineHits: lineHits.sorted(by: lineHitOrder)
                )
            )
            sourcePath = nil
            functions = []
            functionHits = []
            lineHits = []
        }

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = trimmed(String(rawLine))
            if line.isEmpty { continue }
            if line == "end_of_record" {
                finishRecord()
                continue
            }
            if let value = value(after: "SF:", in: line) {
                finishRecord()
                sourcePath = value
                continue
            }
            if let value = value(after: "FN:", in: line), let comma = value.firstIndex(of: ",") {
                let lineText = String(value[..<comma])
                let name = String(value[value.index(after: comma)...])
                if let lineNumber = Int(lineText), !name.isEmpty {
                    functions.append(LcovFunctionDefinition(line: lineNumber, name: name))
                }
                continue
            }
            if let value = value(after: "FNDA:", in: line), let comma = value.firstIndex(of: ",") {
                let hitText = String(value[..<comma])
                let name = String(value[value.index(after: comma)...])
                if let hits = Int(hitText), !name.isEmpty {
                    functionHits.append(LcovFunctionHit(name: name, hits: hits))
                }
                continue
            }
            if let value = value(after: "DA:", in: line) {
                let parts = value.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count >= 2, let lineNumber = Int(parts[0]), let hits = Int(parts[1]) {
                    lineHits.append(LcovLineHit(line: lineNumber, hits: hits))
                }
                continue
            }
        }
        finishRecord()
        return LcovReport(records: records.sorted { normalizedPath($0.sourcePath) < normalizedPath($1.sourcePath) })
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

private func functionDefinitionOrder(_ lhs: LcovFunctionDefinition, _ rhs: LcovFunctionDefinition) -> Bool {
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
