/// A tiny block-style YAML subset, just expressive enough for the Rule
/// Catalog Manifest's shape (addendum H): nested mappings, `- ` sequences,
/// scalar strings/integers, and the empty flow sequence `[]`.
///
/// `SwiftDebtCore` is deliberately import-free - not even `Foundation` -
/// which `DebtScoringTests.swiftDebtCoreSourcesRemainImportFree` enforces.
/// That rules out both a third-party YAML library and `Foundation`'s
/// `JSONDecoder`, so the manifest is parsed with this small hand-written
/// reader instead. It is not a general YAML implementation: no flow
/// mappings, anchors, multi-line scalars, or tag directives.
enum YAMLNode {
    case scalar(String)
    case sequence([Self])
    case mapping([(key: String, value: Self)])

    subscript(key: String) -> Self? {
        guard case .mapping(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    var sequenceItems: [Self]? {
        guard case .sequence(let items) = self else { return nil }
        return items
    }

    var stringValue: String? {
        guard case .scalar(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        stringValue.flatMap { Int($0) }
    }
}

enum MinimalYAMLParser {
    static func parse(_ text: String) throws -> YAMLNode {
        let lines = preprocess(text)
        guard !lines.isEmpty else { return .mapping([]) }
        var index = 0
        return try parseNode(lines, &index, indent: lines[0].indent)
    }

    private struct Line {
        let indent: Int
        let content: String
    }

    private static func preprocess(_ text: String) -> [Line] {
        var result: [Line] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = rawLine
            if line.hasSuffix("\r") { line = line.dropLast() }
            var indent = 0
            for character in line {
                guard character == " " else { break }
                indent += 1
            }
            let trimmed = rtrim(String(line.drop(while: { $0 == " " })))
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            result.append(Line(indent: indent, content: trimmed))
        }
        return result
    }

    private static func parseNode(
        _ lines: [Line], _ index: inout Int, indent: Int
    ) throws -> YAMLNode {
        guard index < lines.count else { return .mapping([]) }
        if isSequenceMarker(lines[index].content) {
            return try parseSequence(lines, &index, indent: indent)
        }
        return try parseMapping(lines, &index, indent: indent)
    }

    private static func isSequenceMarker(_ content: String) -> Bool {
        content == "-" || content.hasPrefix("- ")
    }

    /// Whether a sequence item's inline content starts a nested mapping
    /// (`key: value` or `key:` with children on following lines) as opposed
    /// to being a bare scalar item (`- syntax`).
    private static func isMappingStart(_ content: String) -> Bool {
        content.hasSuffix(":") || content.firstRange(of: ": ") != nil
    }

    private static func parseSequence(
        _ lines: [Line], _ index: inout Int, indent: Int
    ) throws -> YAMLNode {
        var items: [YAMLNode] = []
        while index < lines.count, lines[index].indent == indent,
            isSequenceMarker(lines[index].content) {
            let afterDash = String(lines[index].content.dropFirst())
            let leadingSpaces = afterDash.prefix { $0 == " " }.count
            let remainder = ltrim(afterDash)
            index += 1
            if remainder.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    items.append(try parseNode(lines, &index, indent: lines[index].indent))
                } else {
                    items.append(.scalar(""))
                }
                continue
            }
            guard isMappingStart(remainder) else {
                // A plain scalar list item, e.g. "- syntax": no nested lines belong to it.
                items.append(.scalar(unquote(remainder)))
                continue
            }
            let virtualIndent = indent + 1 + leadingSpaces
            var subLines = [Line(indent: virtualIndent, content: remainder)]
            while index < lines.count, lines[index].indent > indent {
                subLines.append(lines[index])
                index += 1
            }
            var subIndex = 0
            items.append(try parseNode(subLines, &subIndex, indent: virtualIndent))
        }
        return .sequence(items)
    }

    private static func parseMapping(
        _ lines: [Line], _ index: inout Int, indent: Int
    ) throws -> YAMLNode {
        var pairs: [(key: String, value: YAMLNode)] = []
        while index < lines.count, lines[index].indent == indent,
            !isSequenceMarker(lines[index].content) {
            let (key, rawValue) = try splitKeyValue(lines[index].content)
            index += 1
            if rawValue.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    pairs.append((key, try parseNode(lines, &index, indent: lines[index].indent)))
                } else {
                    pairs.append((key, .mapping([])))
                }
            } else if rawValue == "[]" {
                pairs.append((key, .sequence([])))
            } else {
                pairs.append((key, .scalar(unquote(rawValue))))
            }
        }
        return .mapping(pairs)
    }

    private static func splitKeyValue(_ content: String) throws -> (String, String) {
        if let range = content.firstRange(of: ": ") {
            let key = rtrim(String(content[..<range.lowerBound]))
            let value = ltrim(String(content[range.upperBound...]))
            return (key, value)
        }
        if content.hasSuffix(":") {
            return (String(content.dropLast()), "")
        }
        throw RuleManifestError.malformedDocument(
            reason: "expected 'key: value' in line '\(content)'")
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("'") && value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func ltrim(_ value: String) -> String {
        String(value.drop(while: { $0 == " " }))
    }

    private static func rtrim(_ value: String) -> String {
        var value = value
        while value.last == " " { value.removeLast() }
        return value
    }
}
