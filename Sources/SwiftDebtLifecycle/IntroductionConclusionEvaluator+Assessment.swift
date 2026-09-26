import SwiftDebtCore

extension IntroductionConclusionEvaluator {
    func assess(
        _ record: IntroductionHistoryRevision,
        openingDetection: ObservedDetection,
        openingSnapshot: ObservationSnapshot,
        rule: SnapshotRule
    ) throws -> RevisionAssessment {
        if let reason = record.unavailableReason {
            return .incomplete([reason], semanticComparisons: [])
        }
        guard let observation = record.observation else {
            return .incomplete(
                [
                    try LifecycleReason(
                        code: "history-observation-unavailable",
                        message: "Revision \(record.revision.rawValue) has no historical observation."
                    )
                ],
                semanticComparisons: []
            )
        }
        guard observation.provenance.scope.isCompleteRepository else {
            return .incomplete(
                [
                    try LifecycleReason(
                        code: "historical-scope-incomplete",
                        message: "Revision \(record.revision.rawValue) was not analyzed with repository scope."
                    )
                ],
                semanticComparisons: []
            )
        }
        guard observation.provenance.engineVersion == openingSnapshot.provenance.engineVersion else {
            return .incomplete(
                [
                    try LifecycleReason(
                        code: "historical-engine-incomparable",
                        message: "Revision \(record.revision.rawValue) used a different engine version."
                    )
                ],
                semanticComparisons: []
            )
        }
        guard observation.provenance.capabilities == openingSnapshot.provenance.capabilities,
            observation.provenance.capabilities.allSatisfy({ $0.state.supportsComparison })
        else {
            return .incomplete(
                [
                    try LifecycleReason(
                        code: "historical-capability-incomparable",
                        message: "Revision \(record.revision.rawValue) lacks comparable analysis capabilities."
                    )
                ],
                semanticComparisons: []
            )
        }
        guard let historicalRule = observation.rules.first(where: { $0.identity == rule.identity }) else {
            return .incomplete(
                [
                    try LifecycleReason(
                        code: "historical-rule-omitted",
                        message: "Revision \(record.revision.rawValue) omitted the Finding's rule."
                    )
                ],
                semanticComparisons: []
            )
        }
        let atomics = observation.atomicObservations.filter { $0.rule == historicalRule }
        guard atomics.count == observation.sources.count, !atomics.isEmpty,
            atomics.allSatisfy({ $0.outcome.isCommitted })
        else {
            return .incomplete(
                [
                    try LifecycleReason(
                        code: "historical-observation-incomplete",
                        message:
                            "Revision \(record.revision.rawValue) lacks committed target-rule evidence for every SourceUnit."
                    )
                ],
                semanticComparisons: []
            )
        }
        guard let anchor = openingDetection.structuralEvidence else {
            return .incomplete(
                [
                    try LifecycleReason(
                        code: "opening-structural-evidence-unavailable",
                        message: "The Finding's First Observation lacks engine-owned structural evidence."
                    )
                ],
                semanticComparisons: []
            )
        }

        let detections = observation.detections.filter { $0.rule == historicalRule }
        let exact = detections.filter { $0.structuralEvidence == anchor }
        if exact.count == 1, let detection = exact.first,
            detection.location.sourcePath == openingDetection.location.sourcePath
        {
            return try semanticAssessment(
                claim: .continuity,
                priorObservation: observation,
                priorRule: historicalRule,
                openingSnapshot: openingSnapshot,
                openingRule: rule,
                compatible: { .present($0) }
            )
        }
        if !exact.isEmpty {
            let comparison = try SemanticComparisonEvaluator().assess(
                claim: .continuity,
                priorSnapshot: observation,
                priorRule: historicalRule,
                currentSnapshot: openingSnapshot,
                currentRule: rule
            )
            return .incomplete(
                comparison.reasons + [
                    try LifecycleReason(
                        code: "historical-cross-file-continuity-unsupported",
                        message:
                            "Revision \(record.revision.rawValue) has exact structural candidates without persisted rename proof."
                    )
                ],
                semanticComparisons: [comparison.basis]
            )
        }

        let partial = detections.filter { detection in
            guard let candidate = detection.structuralEvidence,
                candidate.algorithm == anchor.algorithm
            else { return detection.location.sourcePath == openingDetection.location.sourcePath }
            return detection.location.sourcePath == openingDetection.location.sourcePath
                || candidate.subjectDigest == anchor.subjectDigest
                || (candidate.enclosingDeclarationDigest != nil
                    && candidate.enclosingDeclarationDigest == anchor.enclosingDeclarationDigest)
        }
        guard partial.isEmpty else {
            let comparison = try SemanticComparisonEvaluator().assess(
                claim: .continuity,
                priorSnapshot: observation,
                priorRule: historicalRule,
                currentSnapshot: openingSnapshot,
                currentRule: rule
            )
            return .incomplete(
                comparison.reasons + [
                    try LifecycleReason(
                        code: "historical-continuity-ambiguous",
                        message:
                            "Revision \(record.revision.rawValue) contains a credible but non-unique structural predecessor."
                    )
                ],
                semanticComparisons: [comparison.basis]
            )
        }
        return try semanticAssessment(
            claim: .absence,
            priorObservation: observation,
            priorRule: historicalRule,
            openingSnapshot: openingSnapshot,
            openingRule: rule,
            compatible: { .absent($0) }
        )
    }

    private func semanticAssessment(
        claim: SemanticCompatibilityClaim,
        priorObservation: ObservationSnapshot,
        priorRule: SnapshotRule,
        openingSnapshot: ObservationSnapshot,
        openingRule: SnapshotRule,
        compatible: (SemanticComparisonBasis) -> RevisionAssessment
    ) throws -> RevisionAssessment {
        let comparison = try SemanticComparisonEvaluator().assess(
            claim: claim,
            priorSnapshot: priorObservation,
            priorRule: priorRule,
            currentSnapshot: openingSnapshot,
            currentRule: openingRule
        )
        guard comparison.isCompatible else {
            return .incomplete(comparison.reasons, semanticComparisons: [comparison.basis])
        }
        return compatible(comparison.basis)
    }

}
