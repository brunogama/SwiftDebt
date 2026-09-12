import Foundation
import Testing

@testable import SCMACore

@Suite("Debt analysis domain and scoring")
struct DebtScoringTests {
    @Test func scmaCoreSourcesRemainImportFree() throws {
        let importDeclarations = try scmaCoreSourceFiles().flatMap { file in
            try sourceFindings(in: file) { line, _ in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("import ")
            }
        }

        #expect(importDeclarations.isEmpty, "SCMACore must not import modules: \(importDeclarations)")
    }

    @Test func debtScoringSourceDeclaresNoAmbientClockOrMutableState() throws {
        let scoringSourceNames = Set(["DebtScoring.swift", "DebtScoreModels.swift"])
        let scoringSources = try scmaCoreSourceFiles().filter { scoringSourceNames.contains($0.lastPathComponent) }
        let findings = try scoringSources.flatMap { file in
            try sourceFindings(in: file) { line, trimmed in
                line.hasPrefix("var ")
                    || line.hasPrefix("public var ")
                    || line.hasPrefix("internal var ")
                    || line.hasPrefix("private var ")
                    || line.hasPrefix("fileprivate var ")
                    || trimmed.contains("static var ")
                    || trimmed.contains("Date")
                    || trimmed.contains("Clock")
                    || trimmed.contains(".now")
                    || trimmed.contains("ProcessInfo")
                    || trimmed.contains("Dispatch")
                    || trimmed.contains("TaskLocal")
            }
        }

        #expect(findings.isEmpty, "Debt scoring must not use ambient clock or mutable shared state: \(findings)")
    }

    @Test func optionalUnavailableEvidenceIsRenormalizedNotZeroed() throws {
        let score = DebtScoring().score(evidence: [
            evidence("complexity", weight: 2, score: 80, rawValue: "ccf=12"),
            evidence("coverage", weight: 3, score: nil, rawValue: "missing", availability: .unavailable(reason: "no LCOV")),
        ])

        #expect(score.value == 80)
        #expect(score.priority == .high)
        #expect(score.breakdown.totalConfiguredWeight == 5)
        #expect(score.breakdown.totalAvailableWeight == 2)
        #expect(score.breakdown.contributions.map(\.evidenceID) == ["complexity"])
        #expect(score.breakdown.contributions.first?.effectiveWeight == 1)
        #expect(score.breakdown.unavailableEvidence.first?.evidenceID == "coverage")
        #expect(score.breakdown.unavailableEvidence.first?.reason == "no LCOV")
    }

    @Test func requiredUnavailableEvidenceWithholdsCompositeScore() {
        let score = DebtScoring().score(evidence: [
            evidence("complexity", weight: 1, score: 90, rawValue: "ccf=18"),
            evidence(
                "bindings",
                requirement: .required,
                weight: 1,
                score: nil,
                rawValue: "missing",
                availability: .unavailable(reason: "compiler binding unavailable")
            ),
        ])

        #expect(score.value == nil)
        #expect(score.priority == nil)
        #expect(score.breakdown.totalAvailableWeight == 1)
        #expect(score.breakdown.contributions.map(\.evidenceID) == ["complexity"])
        #expect(score.breakdown.unavailableEvidence.map(\.evidenceID) == ["bindings"])
    }

    @Test func everyOptionalMissingEvidenceCombinationRenormalizesAvailableWeights() throws {
        let base = [
            evidence("complexity", weight: 2, score: 90, rawValue: "ccf=21"),
            evidence("coverage", weight: 3, score: 30, rawValue: "line=30%"),
            evidence("history", weight: 5, score: 60, rawValue: "churn=6"),
        ]
        for mask in 0..<8 {
            let scenario = base.enumerated().map { index, item in
                mask & (1 << index) == 0
                    ? item
                    : evidence(
                        item.id,
                        weight: item.weight,
                        score: nil,
                        rawValue: "missing",
                        availability: .unavailable(reason: "unavailable in scenario")
                    )
            }
            let score = DebtScoring().score(evidence: scenario)
            let available = scenario.filter(\.availability.isAvailable)
            if available.isEmpty {
                #expect(score.value == nil, "mask: \(mask)")
                #expect(score.breakdown.totalAvailableWeight == 0, "mask: \(mask)")
            } else {
                let availableWeight = available.reduce(0.0) { $0 + $1.weight }
                let expected = available.reduce(0.0) { partial, evidence in
                    partial + (evidence.normalizedScore! * evidence.weight / availableWeight)
                }
                #expect(score.value == expected, "mask: \(mask)")
                #expect(score.breakdown.totalAvailableWeight == availableWeight, "mask: \(mask)")
            }
        }
    }

    @Test func scoringIsDeterministicAcrossInputOrder() {
        let forward = [
            evidence("coverage", weight: 3, score: 40, rawValue: "line=40%"),
            evidence("complexity", weight: 2, score: 100, rawValue: "ccf=25"),
            evidence("history", weight: 5, score: nil, rawValue: "missing", availability: .unavailable(reason: "no git")),
        ]
        let reverse = Array(forward.reversed())

        let first = DebtScoring().score(evidence: forward)
        let second = DebtScoring().score(evidence: reverse)

        #expect(first == second)
        for _ in 0..<25 {
            #expect(DebtScoring().score(evidence: forward) == first)
            #expect(DebtScoring().score(evidence: reverse) == first)
        }
        #expect(first.breakdown.contributions.map(\.evidenceID) == ["complexity", "coverage"])
        #expect(first.breakdown.unavailableEvidence.map(\.evidenceID) == ["history"])
    }

    @Test func evidenceWithMatchingIDAndKindHasDeterministicContributionOrder() {
        let forward = [
            evidence("duplicate", weight: 1, score: 30, rawValue: "raw-b", note: "note-a"),
            evidence("duplicate", weight: 1, score: 20, rawValue: "raw-a", note: "note-b"),
            evidence("duplicate", weight: 1, score: 10, rawValue: "raw-a", note: "note-a"),
        ]
        let reverse = Array(forward.reversed())

        let first = DebtScoring().score(evidence: forward)
        let second = DebtScoring().score(evidence: reverse)

        #expect(first == second)
        #expect(first.breakdown.contributions.map(\.rawValue) == ["raw-a", "raw-a", "raw-b"])
        #expect(first.breakdown.contributions.map(\.note) == ["note-a", "note-b", "note-a"])
    }

    @Test(arguments: [
        (0.0, Priority.low),
        (39.999, Priority.low),
        (40.0, Priority.medium),
        (69.999, Priority.medium),
        (70.0, Priority.high),
        (84.999, Priority.high),
        (85.0, Priority.critical),
        (100.0, Priority.critical),
    ])
    func priorityBoundaries(score: Double, expected: Priority) {
        #expect(PriorityThresholds().classify(score) == expected)
    }

    @Test func rawEvidenceAndWeightsArePreservedInExplanation() throws {
        let score = DebtScoring().score(evidence: [
            evidence("coverage", kind: "coverage", weight: 3, score: 25, rawValue: "covered=25/100"),
            evidence("complexity", kind: "metric", weight: 1, score: 75, rawValue: "ccf=15"),
        ])

        let coverage = try #require(score.breakdown.contributions.first { $0.evidenceID == "coverage" })
        #expect(coverage.kind == "coverage")
        #expect(coverage.rawValue == "covered=25/100")
        #expect(coverage.configuredWeight == 3)
        #expect(coverage.effectiveWeight == 0.75)
        #expect(coverage.contribution == 18.75)
    }

    @Test func scoreInputBoundariesAreClampedBeforeContribution() {
        let score = DebtScoring().score(evidence: [
            evidence("negative", weight: 1, score: -10, rawValue: "risk=-10"),
            evidence("oversized", weight: 1, score: 120, rawValue: "risk=120"),
        ])

        #expect(score.value == 50)
        #expect(score.priority == .medium)
        #expect(score.breakdown.contributions.map(\.normalizedScore) == [0, 100])
        #expect(score.breakdown.contributions.allSatisfy { $0.note?.contains("clamped") == true })
    }

    @Test func paperScoringRemainsSeparateFromDebtScoring() {
        let inputs = ScoreInputs(methodCount: 4, propertyCount: 2, parameterCount: 8, duplicateLines: 12, totalLines: 100)
        let paper = PaperScoring().score(metric: .dc, values: [12], inputs: inputs, mode: .paper)
        let debt = DebtScoring().score(evidence: [evidence("dc", weight: 1, score: 80, rawValue: "duplicated=12")])

        #expect(paper.value == 2 / 150.4)
        #expect(debt.value == 80)
        #expect(debt.priority == .high)
    }

    @Test func domainSupportsCallableTypeFileAndModuleAggregationContracts() {
        let callable = entity("callable:App.Processor.process", level: .callable, file: "Sources/Processor.swift", line: 12)
        let type = entity("type:App.Processor", level: .type, file: "Sources/Processor.swift", line: 1)
        let file = entity("file:Sources/Processor.swift", level: .file, file: "Sources/Processor.swift")
        let module = entity("module:App", level: .module, file: nil)
        let score = DebtScoring().score(evidence: [evidence("complexity", weight: 1, score: 70, rawValue: "ccf=12")])
        let aggregation = DebtAggregation(
            id: type.id,
            level: type.level,
            displayName: type.displayName,
            location: type.location,
            memberItemIDs: [callable.id],
            score: score
        )

        #expect([callable.level, type.level, file.level, module.level] == [.callable, .type, .file, .module])
        #expect(aggregation.memberItemIDs == ["callable:App.Processor.process"])
        #expect(aggregation.score?.value == 70)
    }

    private func scmaCoreSourceFiles() throws -> [URL] {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("Sources/SCMACore", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil))
        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { relativePath($0) < relativePath($1) }
    }

    private func sourceFindings(in file: URL, matching predicate: (String, String) -> Bool) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { lineIndex, line in
                let line = String(line)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard predicate(line, trimmed) else { return nil }
                return "\(relativePath(file)):\(lineIndex + 1): \(trimmed)"
            }
    }

    private func relativePath(_ file: URL) -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rootPath = repositoryRoot.path + "/"
        return file.path.hasPrefix(rootPath) ? String(file.path.dropFirst(rootPath.count)) : file.path
    }

    private func evidence(
        _ id: String,
        kind: String = "metric",
        requirement: DebtEvidenceRequirement = .optional,
        weight: Double,
        score: Double?,
        rawValue: String,
        availability: DebtEvidenceAvailability = .available,
        note: String? = nil
    ) -> DebtEvidence {
        DebtEvidence(
            id: id,
            kind: kind,
            requirement: requirement,
            availability: availability,
            weight: weight,
            normalizedScore: score,
            rawValue: rawValue,
            note: note
        )
    }

    private func entity(_ id: String, level: DebtAggregationLevel, file: String?, line: Int? = nil) -> DebtEntity {
        DebtEntity(
            id: id,
            displayName: id,
            level: level,
            location: DebtLocation(module: "App", file: file, line: line)
        )
    }
}
