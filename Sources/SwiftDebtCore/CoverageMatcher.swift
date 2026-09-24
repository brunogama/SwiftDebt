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
            if let matchedPath = match.record?.record.sourcePath { matchedRecordPaths.insert(matchedPath) }
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
                        .sourcePathExact, .sourcePathSuffix, .functionNameExact, .functionNameSuffix,
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

    private func match(entity: DebtEntity, records: [IndexedRecord]) -> Match {
        let sourcePath = entity.location.file.map(normalizedPath)
        guard let sourcePath else {
            return Match(
                attempted: [.sourcePathExact, .sourcePathSuffix], availability: .missingFile,
                message: "Debt entity has no source file")
        }
        guard let record = exactRecord(for: sourcePath, in: records) ?? suffixRecord(for: sourcePath, in: records)
        else {
            return Match(
                attempted: [.sourcePathExact, .sourcePathSuffix],
                availability: .missingFile,
                message: "No LCOV source file matched \(sourcePath)"
            )
        }
        let pathStrategy: CoverageMatchingStrategy =
            record.normalizedPath == sourcePath ? .sourcePathExact : .sourcePathSuffix
        let pathConfidence: CoverageMatchingConfidence = pathStrategy == .sourcePathExact ? .exact : .high
        if entity.level == .file || entity.level == .module || entity.level == .type {
            guard !record.record.lineHits.isEmpty else {
                return Match(
                    record: record,
                    attempted: [pathStrategy, .executableLine],
                    availability: .unmatchedEntity,
                    confidence: .unmatched,
                    message: "Matched source file has no line coverage records"
                )
            }
            let covered = record.record.lineHits.filter { $0.hits > 0 }.count
            return Match(
                record: record,
                covered: covered,
                total: record.record.lineHits.count,
                attempted: [pathStrategy, .executableLine],
                availability: covered == 0 ? .zeroCoverage : .measuredCoverage,
                confidence: pathConfidence,
                message: coverageMessage(covered: covered, total: record.record.lineHits.count)
            )
        }

        let names = candidateNames(for: entity)
        if let function = exactFunction(for: names, in: record.record) {
            return Match(
                record: record,
                functionName: function.name,
                covered: function.hits > 0 ? 1 : 0,
                total: 1,
                attempted: [pathStrategy, .functionNameExact],
                availability: function.hits > 0 ? .measuredCoverage : .zeroCoverage,
                confidence: .exact,
                message: function.hits > 0
                    ? "Matched LCOV function with executed hits" : "Matched LCOV function with zero hits"
            )
        }
        if let function = suffixFunction(for: names, in: record.record) {
            return Match(
                record: record,
                functionName: function.name,
                covered: function.hits > 0 ? 1 : 0,
                total: 1,
                attempted: [pathStrategy, .functionNameExact, .functionNameSuffix],
                availability: function.hits > 0 ? .measuredCoverage : .zeroCoverage,
                confidence: .high,
                message: function.hits > 0
                    ? "Matched LCOV function suffix with executed hits" : "Matched LCOV function suffix with zero hits"
            )
        }
        if let line = entity.location.line, let function = functionStarting(at: line, in: record.record) {
            return Match(
                record: record,
                functionName: function.name,
                covered: function.hits > 0 ? 1 : 0,
                total: 1,
                attempted: [pathStrategy, .functionNameExact, .functionNameSuffix, .functionStartLine],
                availability: function.hits > 0 ? .measuredCoverage : .zeroCoverage,
                confidence: .fallback,
                message: function.hits > 0
                    ? "Matched LCOV function start line with executed hits"
                    : "Matched LCOV function start line with zero hits"
            )
        }
        if let line = entity.location.line, let hit = record.record.lineHits.first(where: { $0.line == line }) {
            return Match(
                record: record,
                covered: hit.hits > 0 ? 1 : 0,
                total: 1,
                attempted: [
                    pathStrategy, .functionNameExact, .functionNameSuffix, .functionStartLine, .executableLine,
                ],
                availability: hit.hits > 0 ? .measuredCoverage : .zeroCoverage,
                confidence: .fallback,
                message: hit.hits > 0
                    ? "Matched executable line with executed hits" : "Matched executable line with zero hits"
            )
        }
        return Match(
            record: record,
            attempted: [pathStrategy, .functionNameExact, .functionNameSuffix, .functionStartLine, .executableLine],
            availability: .unmatchedEntity,
            confidence: .unmatched,
            message: "Matched source file, but no LCOV function or executable line matched the entity"
        )
    }

    private func exactRecord(for path: String, in records: [IndexedRecord]) -> IndexedRecord? {
        records.first { $0.normalizedPath == path }
    }

    private func suffixRecord(for path: String, in records: [IndexedRecord]) -> IndexedRecord? {
        records.first { isPathSuffix(path, of: $0.normalizedPath) || isPathSuffix($0.normalizedPath, of: path) }
    }

    private func exactFunction(for names: [String], in record: LcovRecord) -> LcovFunctionHit? {
        record.functionHits.first { hit in names.contains(hit.name) }
    }

    private func suffixFunction(for names: [String], in record: LcovRecord) -> LcovFunctionHit? {
        record.functionHits.first { hit in
            names.contains { name in name.hasSuffix("." + hit.name) || hit.name.hasSuffix("." + name) }
        }
    }

    private func functionStarting(at line: Int, in record: LcovRecord) -> LcovFunctionHit? {
        let names = Set(record.functions.lazy.filter { $0.line == line }.map(\.name))
        guard names.count == 1, let name = names.first else { return nil }
        return record.functionHits.first { $0.name == name }
    }

    private func candidateNames(for entity: DebtEntity) -> [String] {
        var names = [entity.displayName, entity.id]
        for prefix in ["callable:", "type:", "file:", "module:"] where entity.id.hasPrefix(prefix) {
            names.append(String(entity.id.dropFirst(prefix.count)))
        }
        return Array(Set(names)).sorted()
    }

    private func coverageEvidence(for entity: DebtEntity, match: Match) -> DebtEvidence {
        let availability = evidenceAvailability(for: match)
        let score: Double?
        let raw: String
        if match.total > 0 {
            let percentage = Double(match.covered) / Double(match.total) * 100
            score = percentage
            raw =
                "covered=\(match.covered)/\(match.total);coverage=\(format(percentage))%;confidence=\(match.confidence.rawValue)"
        } else {
            score = nil
            raw = "coverage=unavailable;confidence=\(match.confidence.rawValue)"
        }
        return DebtEvidence(
            id: "\(entity.id):coverage:lcov",
            kind: "coverage.lcov",
            requirement: .optional,
            availability: availability,
            weight: 1,
            normalizedScore: score,
            rawValue: raw,
            location: entity.location,
            note:
                "Coverage dampener matched with strategies \(match.attempted.map(\.rawValue).joined(separator: ">")); \(match.message)"
        )
    }

    private func evidenceAvailability(for match: Match) -> DebtEvidenceAvailability {
        switch match.availability {
        case .measuredCoverage:
            return DebtEvidenceAvailability(state: .measuredCoverage)
        case .zeroCoverage:
            return DebtEvidenceAvailability(state: .zeroCoverage)
        case .missingFile:
            return DebtEvidenceAvailability(state: .missingFile, reason: match.message)
        case .unmatchedEntity:
            return DebtEvidenceAvailability(state: .unmatchedEntity, reason: match.message)
        }
    }

    private func diagnostic(for entity: DebtEntity, match: Match) -> CoverageDiagnostic {
        CoverageDiagnostic(
            entityID: entity.id,
            entityDisplayName: entity.displayName,
            sourcePath: entity.location.file,
            matchedSourcePath: match.record?.record.sourcePath,
            matchedFunction: match.functionName,
            availability: match.availability,
            confidence: match.confidence,
            attemptedStrategies: match.attempted,
            message: match.message
        )
    }
}

private struct IndexedRecord: Sendable {
    let record: LcovRecord
    let normalizedPath: String
}

private struct Match: Sendable {
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
    if (lhs.entityID ?? "") != (rhs.entityID ?? "") { return (lhs.entityID ?? "") < (rhs.entityID ?? "") }
    if (lhs.sourcePath ?? "") != (rhs.sourcePath ?? "") { return (lhs.sourcePath ?? "") < (rhs.sourcePath ?? "") }
    return lhs.message < rhs.message
}

private func normalize(_ path: String, root: String?) -> String {
    let normalized = normalizedPath(path)
    guard let root, normalized == root || normalized.hasPrefix(root + "/") else { return normalized }
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

private func isPathSuffix(_ suffix: String, of path: String) -> Bool {
    path == suffix || path.hasSuffix("/" + suffix)
}

private func coverageMessage(covered: Int, total: Int) -> String {
    "Matched \(covered) covered executable lines out of \(total)"
}

private func format(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == Double(Int(rounded)) { return "\(Int(rounded))" }
    return "\(rounded)"
}
