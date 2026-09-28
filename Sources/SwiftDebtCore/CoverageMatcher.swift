public struct CoverageMatcher: Sendable {
    public init() {}

    public func match(report: LcovReport, entities: [DebtEntity], repositoryRoot: String? = nil)
        -> CoverageMatchingResult
    {
        let root = repositoryRoot.map(normalizedPath)
        let records = report.records.sorted(by: recordOrder)
        let indexedRecords = records.map { record in
            IndexedRecord(record: record, normalizedPath: normalize(record.sourcePath, root: root))
        }
        var matchedRecordPaths: Set<String> = []
        var evidence: [DebtEvidence] = []
        var diagnostics: [CoverageDiagnostic] = []

        for entity in entities.sorted(by: entityOrder) {
            let match = match(entity: entity, records: indexedRecords)
            if let matchedPath = match.record?.record.sourcePath {
                matchedRecordPaths.insert(matchedPath)
            }
            evidence.append(coverageEvidence(for: entity, match: match))
            diagnostics.append(diagnostic(for: entity, match: match))
        }

        for record in records where !matchedRecordPaths.contains(record.sourcePath) {
            diagnostics.append(
                CoverageDiagnostic(
                    entityID: nil,
                    entityDisplayName: nil,
                    sourcePath: record.sourcePath,
                    matchedSourcePath: nil,
                    matchedFunction: nil,
                    availability: .unmatchedEntity,
                    confidence: .unmatched,
                    attemptedStrategies: [
                        .sourcePathExact, .sourcePathSuffix, .functionNameExact,
                        .functionNameSuffix,
                    ],
                    message: "LCOV record did not match any debt entity"
                )
            )
        }

        return CoverageMatchingResult(
            evidence: evidence.sorted(by: evidenceOrder),
            diagnostics: diagnostics.sorted(by: diagnosticOrder)
        )
    }

    public func renderDiagnostics(_ diagnostics: [CoverageDiagnostic]) -> String {
        diagnostics.sorted(by: diagnosticOrder).map { diagnostic in
            let subject = diagnostic.entityDisplayName ?? diagnostic.sourcePath ?? "<unknown>"
            let source = diagnostic.matchedSourcePath ?? diagnostic.sourcePath ?? "<none>"
            let function = diagnostic.matchedFunction.map { " function=\($0)" } ?? ""
            let strategies = diagnostic.attemptedStrategies.map(\.rawValue).joined(separator: ">")
            return
                "coverage: \(subject): \(diagnostic.availability.rawValue) confidence=\(diagnostic.confidence.rawValue) source=\(source)\(function) strategies=\(strategies) - \(diagnostic.message)"
        }.joined(separator: "\n") + (diagnostics.isEmpty ? "" : "\n")
    }

}

struct IndexedRecord: Sendable {
    let record: LcovRecord
    let normalizedPath: String
}

struct Match: Sendable {
    var record: IndexedRecord?
    var functionName: String?
    var covered: Int = 0
    var total: Int = 0
    var attempted: [CoverageMatchingStrategy]
    var availability: CoverageAvailability
    var confidence: CoverageMatchingConfidence = .unmatched
    var message: String
}

private func recordOrder(_ lhs: LcovRecord, _ rhs: LcovRecord) -> Bool {
    normalizedPath(lhs.sourcePath) < normalizedPath(rhs.sourcePath)
}

private func entityOrder(_ lhs: DebtEntity, _ rhs: DebtEntity) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    return lhs.displayName < rhs.displayName
}

private func evidenceOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
    (lhs.id, lhs.rawValue) < (rhs.id, rhs.rawValue)
}

private func diagnosticOrder(_ lhs: CoverageDiagnostic, _ rhs: CoverageDiagnostic) -> Bool {
    if (lhs.entityID ?? "") != (rhs.entityID ?? "") {
        return (lhs.entityID ?? "") < (rhs.entityID ?? "")
    }
    if (lhs.sourcePath ?? "") != (rhs.sourcePath ?? "") {
        return (lhs.sourcePath ?? "") < (rhs.sourcePath ?? "")
    }
    return lhs.message < rhs.message
}

private func normalize(_ path: String, root: String?) -> String {
    let normalized = normalizedPath(path)
    guard let root, normalized == root || normalized.hasPrefix(root + "/") else {
        return normalized
    }
    return String(normalized.dropFirst(root.count + (normalized == root ? 0 : 1)))
}

func normalizedPath(_ path: String) -> String {
    let replaced = path.map { $0 == "\\" ? "/" : String($0) }.joined()
    let absolute = replaced.hasPrefix("/")
    var parts: [String] = []
    for part in replaced.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
        if part == "." { continue }
        if part == ".." {
            if !parts.isEmpty { _ = parts.removeLast() }
            continue
        }
        parts.append(part)
    }
    let joined = parts.joined(separator: "/")
    return absolute ? "/" + joined : joined
}
