extension CoverageMatcher {
    func exactRecord(for path: String, in records: [IndexedRecord]) -> IndexedRecord? {
        records.first { $0.normalizedPath == path }
    }

    func suffixRecord(for path: String, in records: [IndexedRecord]) -> IndexedRecord? {
        records.first {
            isPathSuffix(path, of: $0.normalizedPath) || isPathSuffix($0.normalizedPath, of: path)
        }
    }

    func exactFunction(for names: [String], in record: LcovRecord) -> LcovFunctionHit? {
        record.functionHits.first { hit in names.contains(hit.name) }
    }

    func suffixFunction(for names: [String], in record: LcovRecord) -> LcovFunctionHit? {
        record.functionHits.first { hit in
            names.contains { name in
                name.hasSuffix("." + hit.name) || hit.name.hasSuffix("." + name)
            }
        }
    }

    func functionStarting(at line: Int, in record: LcovRecord) -> LcovFunctionHit? {
        let names = Set(record.functions.lazy.filter { $0.line == line }.map(\.name))
        guard names.count == 1, let name = names.first else { return nil }
        return record.functionHits.first { $0.name == name }
    }

    func candidateNames(for entity: DebtEntity) -> [String] {
        var names = [entity.displayName, entity.id]
        for prefix in ["callable:", "type:", "file:", "module:"] where entity.id.hasPrefix(prefix) {
            names.append(String(entity.id.dropFirst(prefix.count)))
        }
        return Array(Set(names)).sorted()
    }

    func coverageEvidence(for entity: DebtEntity, match: Match) -> DebtEvidence {
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

    func evidenceAvailability(for match: Match) -> DebtEvidenceAvailability {
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

    func diagnostic(for entity: DebtEntity, match: Match) -> CoverageDiagnostic {
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

private func isPathSuffix(_ suffix: String, of path: String) -> Bool {
    path == suffix || path.hasSuffix("/" + suffix)
}

func coverageMessage(covered: Int, total: Int) -> String {
    "Matched \(covered) covered executable lines out of \(total)"
}

private func format(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == Double(Int(rounded)) { return "\(Int(rounded))" }
    return "\(rounded)"
}
