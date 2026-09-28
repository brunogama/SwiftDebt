extension CoverageMatcher {
    func match(entity: DebtEntity, records: [IndexedRecord]) -> Match {
        guard let sourcePath = entity.location.file.map(normalizedPath) else {
            return Match(
                attempted: [.sourcePathExact, .sourcePathSuffix], availability: .missingFile,
                message: "Debt entity has no source file")
        }
        guard
            let record = exactRecord(for: sourcePath, in: records)
                ?? suffixRecord(for: sourcePath, in: records)
        else {
            return Match(
                attempted: [.sourcePathExact, .sourcePathSuffix],
                availability: .missingFile,
                message: "No LCOV source file matched \(sourcePath)"
            )
        }
        let pathStrategy: CoverageMatchingStrategy =
            record.normalizedPath == sourcePath ? .sourcePathExact : .sourcePathSuffix
        let pathConfidence: CoverageMatchingConfidence =
            pathStrategy == .sourcePathExact ? .exact : .high
        if entity.level == .file || entity.level == .module || entity.level == .type {
            return aggregateMatch(
                record: record, strategy: pathStrategy, confidence: pathConfidence)
        }

        let names = candidateNames(for: entity)
        if let function = exactFunction(for: names, in: record.record) {
            return functionMatch(
                record: record, function: function,
                attempted: [pathStrategy, .functionNameExact], confidence: .exact
            )
        }
        if let function = suffixFunction(for: names, in: record.record) {
            return functionMatch(
                record: record, function: function,
                attempted: [pathStrategy, .functionNameExact, .functionNameSuffix],
                confidence: .high
            )
        }
        return fallbackMatch(entity: entity, record: record, pathStrategy: pathStrategy)
    }

    private func aggregateMatch(
        record: IndexedRecord,
        strategy: CoverageMatchingStrategy,
        confidence: CoverageMatchingConfidence
    ) -> Match {
        guard !record.record.lineHits.isEmpty else {
            return Match(
                record: record,
                attempted: [strategy, .executableLine],
                availability: .unmatchedEntity,
                confidence: .unmatched,
                message: "Matched source file has no line coverage records"
            )
        }
        let covered = record.record.lineHits.filter { $0.hits > 0 }.count
        return Match(
            record: record, covered: covered, total: record.record.lineHits.count,
            attempted: [strategy, .executableLine],
            availability: covered == 0 ? .zeroCoverage : .measuredCoverage,
            confidence: confidence,
            message: coverageMessage(covered: covered, total: record.record.lineHits.count)
        )
    }

    private func functionMatch(
        record: IndexedRecord,
        function: LcovFunctionHit,
        attempted: [CoverageMatchingStrategy],
        confidence: CoverageMatchingConfidence
    ) -> Match {
        let description: String
        switch attempted.last {
        case .functionNameSuffix: description = "LCOV function suffix"
        case .functionStartLine: description = "LCOV function start line"
        default: description = "LCOV function"
        }
        return Match(
            record: record, functionName: function.name,
            covered: function.hits > 0 ? 1 : 0, total: 1, attempted: attempted,
            availability: function.hits > 0 ? .measuredCoverage : .zeroCoverage,
            confidence: confidence,
            message: function.hits > 0
                ? "Matched \(description) with executed hits"
                : "Matched \(description) with zero hits"
        )
    }

    private func fallbackMatch(
        entity: DebtEntity, record: IndexedRecord, pathStrategy: CoverageMatchingStrategy
    ) -> Match {
        if let line = entity.location.line,
            let function = functionStarting(at: line, in: record.record)
        {
            return functionMatch(
                record: record, function: function,
                attempted: [
                    pathStrategy, .functionNameExact, .functionNameSuffix, .functionStartLine,
                ],
                confidence: .fallback
            )
        }
        if let line = entity.location.line,
            let hit = record.record.lineHits.first(where: { $0.line == line })
        {
            return Match(
                record: record,
                covered: hit.hits > 0 ? 1 : 0,
                total: 1,
                attempted: [
                    pathStrategy, .functionNameExact, .functionNameSuffix, .functionStartLine,
                    .executableLine,
                ],
                availability: hit.hits > 0 ? .measuredCoverage : .zeroCoverage,
                confidence: .fallback,
                message: hit.hits > 0
                    ? "Matched executable line with executed hits"
                    : "Matched executable line with zero hits"
            )
        }
        return Match(
            record: record,
            attempted: [
                pathStrategy, .functionNameExact, .functionNameSuffix, .functionStartLine,
                .executableLine,
            ],
            availability: .unmatchedEntity,
            confidence: .unmatched,
            message:
                "Matched source file, but no LCOV function or executable line matched the entity"
        )
    }
}
