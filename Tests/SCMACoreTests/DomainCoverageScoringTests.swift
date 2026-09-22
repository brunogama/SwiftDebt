import Foundation
import Testing

@testable import SCMACore

@Suite("SCMACore scoring domain boundaries")
struct DomainCoverageScoringTests {
    @Test("Clone floor cannot hide debt below the duplicate threshold")
    func cloneFloorCannotHideDebtBelowThreshold() {
        let options = AnalysisOptions(thresholds: [.dc: 3], minimumDuplicateLines: 5)

        #expect {
            try options.validate()
        } throws: { error in
            configurationMessage(error)
                == "minimumDuplicateLines must not exceed the DC threshold plus one; otherwise shorter violations would be hidden"
        }
    }

    @Test("Paper-derived scoring rejects a custom clone floor")
    func scoringRejectsCustomCloneFloor() {
        let options = AnalysisOptions(scoring: .paper, minimumDuplicateLines: 2)

        #expect {
            try options.validate()
        } throws: { error in
            configurationMessage(error)
                == "paper/bounded scoring requires minimumDuplicateLines = 11; use scoring = none for a custom clone floor"
        }
    }

    @Test("Duplicate comparison budget must be positive")
    func duplicateComparisonBudgetMustBePositive() {
        let options = AnalysisOptions(maximumDuplicateComparisons: 0)

        #expect {
            try options.validate()
        } throws: { error in
            configurationMessage(error) == "maximumDuplicateComparisons must be positive"
        }
    }

    @Test("Available evidence without a usable score is reported, not silently discarded")
    func availableEvidenceWithoutUsableScoreIsReported() throws {
        let score = DebtScoring().score(evidence: [
            evidence("valid", weight: 1, score: 80),
            evidence("required-missing", requirement: .required, weight: 1, score: nil),
            evidence("zero-weight", weight: 0, score: 50),
            evidence("negative-weight", weight: -2, score: 50),
        ])

        #expect(score.value == nil)
        #expect(score.priority == nil)
        #expect(score.breakdown.totalConfiguredWeight == 2)
        #expect(score.breakdown.totalAvailableWeight == 1)
        #expect(score.breakdown.contributions.map(\.evidenceID) == ["valid"])
        let missing = try #require(score.breakdown.unavailableEvidence.first { $0.evidenceID == "required-missing" })
        let zeroWeight = try #require(score.breakdown.unavailableEvidence.first { $0.evidenceID == "zero-weight" })
        let negativeWeight = try #require(
            score.breakdown.unavailableEvidence.first { $0.evidenceID == "negative-weight" })
        #expect(missing.reason == "normalized score unavailable")
        #expect(missing.requirement == .required)
        #expect(zeroWeight.reason == "weight is not positive")
        #expect(negativeWeight.configuredWeight == 0)
    }

    @Test("Nil tie breakers keep scoring deterministic in either input order")
    func nilTieBreakersKeepScoringDeterministic() {
        let notePair = [
            evidence("same", weight: 1, score: 40, rawValue: "same", note: "documented"),
            evidence("same", weight: 1, score: 60, rawValue: "same"),
        ]
        let scorePair = [
            evidence("same", weight: 1, score: 50, rawValue: "same", note: "same"),
            evidence("same", weight: 1, score: nil, rawValue: "same", note: "same"),
        ]
        let nilScorePair = [
            evidence("same", weight: 1, score: nil, rawValue: "same", location: DebtLocation(module: "Module")),
            evidence("same", weight: 1, score: nil, rawValue: "same", location: DebtLocation()),
        ]

        let noteScore = DebtScoring().score(evidence: notePair)
        #expect(noteScore == DebtScoring().score(evidence: Array(notePair.reversed())))
        #expect(noteScore.breakdown.contributions.map(\.note) == [nil, "documented"])
        #expect(DebtScoring().score(evidence: scorePair) == DebtScoring().score(evidence: Array(scorePair.reversed())))
        #expect(
            DebtScoring().score(evidence: nilScorePair) == DebtScoring().score(evidence: Array(nilScorePair.reversed()))
        )
    }

    @Test("Clamping preserves an evidence note and explains the adjustment")
    func clampingPreservesEvidenceNote() throws {
        let score = DebtScoring().score(evidence: [
            evidence("bounded", weight: 1, score: 120, note: "reviewed manually")
        ])
        let contribution = try #require(score.breakdown.contributions.first)

        #expect(contribution.normalizedScore == 100)
        #expect(contribution.note == "reviewed manually; normalized score clamped to 0...100")
    }

    @Test("Unknown analysis options are rejected in deterministic key order")
    func unknownAnalysisOptionsAreRejected() {
        let data = Data(#"{"zeta":true,"alpha":true}"#.utf8)

        #expect {
            try JSONDecoder().decode(DebtAnalysisOptions.self, from: data)
        } throws: { error in
            configurationMessage(error) == "Unknown debt analysis configuration keys: alpha, zeta"
        }
    }

    @Test("Empty analysis configuration decodes documented defaults")
    func emptyAnalysisConfigurationDecodesDefaults() throws {
        let options = try JSONDecoder().decode(DebtAnalysisOptions.self, from: Data("{}".utf8))

        #expect(options.preset == .balanced)
        #expect(options.aggregationStrategy == .file)
        #expect(options.categories.isEmpty)
        #expect(options.levels.isEmpty)
    }

    @Test("Lenient preset supplies its documented thresholds and canonical filters")
    func lenientPresetSuppliesDocumentedDefaults() {
        let options = DebtAnalysisOptions(
            preset: .lenient,
            categories: ["swift", "coverage"],
            levels: [.module, .callable]
        )

        #expect(options.problematicItemScoreThreshold == 85)
        #expect(options.scoringPolicy.priorityThresholds == PriorityThresholds(medium: 55, high: 80, critical: 92))
        #expect(options.categories == ["coverage", "swift"])
        #expect(options.levels == [.callable, .module])
    }

    @Test("Debt analysis configuration coding keys remain string-only")
    func debtAnalysisConfigurationCodingKeysRemainStringOnly() {
        #expect {
            try DebtAnalysisOptions(from: CodingKeyProbeDecoder())
        } throws: { error in
            error as? CodingKeyProbeError == .completed
        }
    }

    @Test("Report comparison classifies every item and aggregation relationship")
    func reportComparisonClassifiesEveryRelationship() throws {
        let location = DebtLocation(module: "App", file: "Sources/App.swift", line: 1)
        let unchanged = reportItem(id: "same", score: 10, priority: .low, location: location)
        let beforeChanged = reportItem(
            id: "changed",
            score: nil,
            priority: nil,
            location: location,
            evidenceIDs: ["shared", "old"],
            unavailableIDs: ["missing-old"]
        )
        let afterChanged = reportItem(
            id: "changed",
            score: 50,
            priority: .medium,
            location: location,
            evidenceIDs: ["new", "shared"],
            unavailableIDs: ["missing-new"]
        )
        let unchangedAggregation = reportAggregation(
            id: "same-aggregation", members: ["same"], score: 10, priority: .low)
        let before = report(
            items: [
                unchanged, beforeChanged, reportItem(id: "removed", score: nil, priority: nil, location: location),
            ],
            aggregations: [
                unchangedAggregation,
                reportAggregation(id: "removed-aggregation", members: ["z", "a"], score: nil, priority: nil),
                reportAggregation(id: "changed-aggregation", members: ["old"], score: nil, priority: nil),
            ],
            missingEvidenceIDs: ["shared", "old"]
        )
        let after = report(
            items: [unchanged, afterChanged, reportItem(id: "added", score: 20, priority: .low, location: location)],
            aggregations: [
                unchangedAggregation,
                reportAggregation(id: "added-aggregation", members: ["d", "c"], score: 20, priority: .low),
                reportAggregation(id: "changed-aggregation", members: ["new"], score: 30, priority: .medium),
            ],
            missingEvidenceIDs: ["shared", "new"]
        )

        let comparison = try DebtReportComparator().compare(before: before, after: after)
        let itemChange = try #require(comparison.itemChanges.changed.first)
        let aggregationChange = try #require(comparison.aggregationChanges.changed.first)

        #expect(comparison.summary.addedItemCount == 1)
        #expect(comparison.summary.removedItemCount == 1)
        #expect(comparison.summary.changedItemCount == 1)
        #expect(comparison.itemChanges.unchangedIDs == ["same"])
        #expect(comparison.summary.beforeTotalScore == 10)
        #expect(comparison.summary.afterTotalScore == 80)
        #expect(comparison.summary.totalScoreDelta == 70)
        #expect(itemChange.score.before == nil)
        #expect(itemChange.score.after == 50)
        #expect(itemChange.score.delta == nil)
        #expect(itemChange.evidence.added == ["new"])
        #expect(itemChange.evidence.removed == ["old"])
        #expect(itemChange.unavailableEvidence.added == ["missing-new"])
        #expect(itemChange.unavailableEvidence.removed == ["missing-old"])
        #expect(comparison.aggregationChanges.unchangedIDs == ["same-aggregation"])
        #expect(comparison.aggregationChanges.added.first?.memberItemIDs == ["c", "d"])
        #expect(comparison.aggregationChanges.removed.first?.memberItemIDs == ["a", "z"])
        #expect(aggregationChange.memberItemIDs.added == ["new"])
        #expect(aggregationChange.memberItemIDs.removed == ["old"])
        #expect(comparison.missingEvidence.added == ["item:new"])
        #expect(comparison.missingEvidence.removed == ["item:old"])
    }

    @Test("Every workload identity field participates in comparability")
    func everyWorkloadIdentityFieldParticipatesInComparability() {
        let baseline = benchmark(workload: workload())
        let candidate = benchmark(workload: workload(analysisMode: "incremental", optionalContext: "coverage"))

        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline,
            candidate: candidate,
            budget: budget()
        )

        #expect(!evaluation.comparable)
        #expect(!evaluation.passed)
        #expect(evaluation.reasons == ["analysis mode differs", "optional context differs"])
    }

    @Test("Zero baselines distinguish a new cost from continued zero cost")
    func zeroBaselinesDistinguishNewCostFromContinuedZeroCost() throws {
        let identity = workload()
        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: benchmark(workload: identity, wallClock: 0, memory: 0),
            candidate: benchmark(workload: identity, wallClock: 1, memory: 0),
            budget: budget()
        )

        #expect(try #require(evaluation.wallClockRegressionPercent).isInfinite)
        #expect(evaluation.peakMemoryRegressionPercent == 0)
        #expect(evaluation.reasons == ["wall-clock regression exceeds 10.0%"])
    }

    @Test("Regression exactly at each budget passes")
    func exactRegressionBudgetsPass() {
        let identity = workload()
        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: benchmark(workload: identity, wallClock: 10, memory: 1_000),
            candidate: benchmark(workload: identity, wallClock: 11, memory: 1_150),
            budget: budget()
        )

        #expect(evaluation.comparable)
        #expect(evaluation.passed)
        #expect(evaluation.wallClockRegressionPercent == 10)
        #expect(evaluation.peakMemoryRegressionPercent == 15)
        #expect(evaluation.reasons.isEmpty)
    }

    private func configurationMessage(_ error: any Error) -> String? {
        guard case AnalysisFailure.invalidConfiguration(let message) = error else { return nil }
        return message
    }

    private func evidence(
        _ id: String,
        requirement: DebtEvidenceRequirement = .optional,
        weight: Double,
        score: Double?,
        rawValue: String = "value",
        location: DebtLocation? = nil,
        note: String? = nil
    ) -> DebtEvidence {
        DebtEvidence(
            id: id,
            kind: "metric",
            requirement: requirement,
            weight: weight,
            normalizedScore: score,
            rawValue: rawValue,
            location: location,
            note: note
        )
    }

    private func report(
        items: [DebtReportItem],
        aggregations: [DebtReportAggregation],
        missingEvidenceIDs: [String]
    ) -> DebtReport {
        let missingEvidence = missingEvidenceIDs.map {
            DebtReportMissingEvidence(
                itemID: "item",
                evidenceID: $0,
                kind: "metric",
                requirement: .optional,
                configuredWeight: 1,
                reason: "missing"
            )
        }
        return DebtReport(
            options: DebtAnalysisOptions(),
            summary: DebtAnalysisSummary(
                totalItemCount: items.count,
                rankedItemCount: items.count,
                aggregationCount: aggregations.count,
                unavailableEvidenceCount: missingEvidence.count,
                priorityCounts: [:]
            ),
            items: items,
            aggregations: aggregations,
            compactItems: [],
            missingEvidence: missingEvidence
        )
    }

    private func reportItem(
        id: String,
        score: Double?,
        priority: Priority?,
        location: DebtLocation,
        evidenceIDs: [String] = [],
        unavailableIDs: [String] = []
    ) -> DebtReportItem {
        DebtReportItem(
            id: id,
            displayName: id,
            level: .callable,
            location: location,
            category: "swift",
            score: score,
            priority: priority,
            explanation: "explanation",
            recommendation: "recommendation",
            evidence: evidenceIDs.map { evidence($0, weight: 1, score: score) },
            scoreBreakdown: DebtScoreBreakdown(
                totalConfiguredWeight: Double(evidenceIDs.count + unavailableIDs.count),
                totalAvailableWeight: Double(evidenceIDs.count),
                contributions: [],
                unavailableEvidence: unavailableIDs.map {
                    DebtUnavailableEvidence(
                        evidenceID: $0,
                        kind: "metric",
                        requirement: .optional,
                        configuredWeight: 1,
                        reason: "missing"
                    )
                }
            )
        )
    }

    private func reportAggregation(
        id: String,
        members: [String],
        score: Double?,
        priority: Priority?
    ) -> DebtReportAggregation {
        DebtReportAggregation(
            id: id,
            level: .file,
            displayName: id,
            location: DebtLocation(module: "App", file: "Sources/App.swift"),
            memberItemIDs: members,
            score: score,
            priority: priority
        )
    }

    private func workload(
        analysisMode: String = "baseline",
        optionalContext: String = "none"
    ) -> PerformanceWorkloadIdentity {
        PerformanceWorkloadIdentity(
            analyzer: "SwiftSCMA",
            workloadFamily: "SwiftSCMA",
            inputSHA256: "input",
            commandFingerprint: "scma analyze Sources",
            analysisMode: analysisMode,
            optionalContext: optionalContext
        )
    }

    private func benchmark(
        workload: PerformanceWorkloadIdentity,
        wallClock: Double = 1,
        memory: UInt64 = 100
    ) -> PerformanceBenchmarkResult {
        PerformanceBenchmarkResult(
            workload: workload,
            wallClockSecondsMedian: wallClock,
            peakMemoryBytesMedian: memory
        )
    }

    private func budget() -> PerformanceRegressionBudget {
        PerformanceRegressionBudget(
            name: "test",
            maximumWallClockRegressionPercent: 10,
            maximumPeakMemoryRegressionPercent: 15
        )
    }
}

private enum CodingKeyProbeError: Error, Equatable {
    case completed
    case unexpectedIntegerSupport
    case unexpectedContainer
}

private struct CodingKeyProbeDecoder: Decoder {
    let codingPath: [any CodingKey] = []
    let userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        guard let stringKey = Key(stringValue: "preset"),
            stringKey.intValue == nil,
            Key(intValue: 0) == nil
        else {
            throw CodingKeyProbeError.unexpectedIntegerSupport
        }
        throw CodingKeyProbeError.completed
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw CodingKeyProbeError.unexpectedContainer
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw CodingKeyProbeError.unexpectedContainer
    }
}
