import SwiftDebtCore

struct IntroductionConclusionEvaluator {
    func make(
        finding: Finding,
        attempt: UInt,
        evidence: IntroductionHistoryEvidence,
        artifact: LifecycleArtifact
    ) throws -> IntroductionConclusion {
        guard attempt > 0 else {
            throw LifecycleContractError.invalidArtifact("Introduction attempts must be positive.")
        }
        try validate(evidence)
        guard let openingSnapshot = artifact.snapshot(id: finding.firstObservationSnapshotID),
            let openingDetection = openingSnapshot.detection(id: finding.openingDetectionID)
        else {
            throw LifecycleContractError.invalidArtifact(
                "Introduction evidence references a Finding without its First Observation."
            )
        }

        let expectedStart = gitRevision(of: openingSnapshot)
        guard evidence.boundary.startingRevision == expectedStart else {
            throw LifecycleContractError.invalidArtifact(
                "Introduction evidence must start at the Finding's committed First Observation."
            )
        }

        let records = Dictionary(uniqueKeysWithValues: evidence.revisions.map { ($0.revision, $0) })
        guard let start = evidence.boundary.startingRevision,
            let startRecord = records[start]
        else {
            let reasons =
                try globalBlockers(openingSnapshot: openingSnapshot, evidence: evidence)
                + [
                    LifecycleReason(
                        code: "committed-first-observation-unavailable",
                        message: "The Finding's First Observation has no committed Git revision to inspect."
                    )
                ]
            return IntroductionConclusion(
                findingID: finding.id,
                attempt: attempt,
                kind: .unavailable,
                exactRevision: nil,
                earliestPositiveRevision: nil,
                reasons: unique(reasons),
                evidence: evidence,
                semanticComparisons: []
            )
        }

        let startAssessment = try assess(
            startRecord,
            openingDetection: openingDetection,
            openingSnapshot: openingSnapshot,
            rule: finding.rule
        )
        var traced: TraceResult
        switch startAssessment {
        case .present(let comparison):
            traced = try trace(
                start,
                records: records,
                frontier: Set(evidence.boundary.frontierRevisions),
                openingDetection: openingDetection,
                openingSnapshot: openingSnapshot,
                rule: finding.rule,
                visited: []
            )
            traced.semanticComparisons = uniqueSemanticComparisons(
                traced.semanticComparisons + [comparison]
            )
        case .absent(let comparison):
            traced = TraceResult(
                kind: .unavailable,
                exactRevision: nil,
                earliestPositiveRevision: nil,
                reasons: [
                    try LifecycleReason(
                        code: "opening-positive-not-reproduced",
                        message: "Committed history did not reproduce the Finding at its First Observation revision."
                    )
                ],
                semanticComparisons: [comparison]
            )
        case .incomplete(let reasons, let comparisons):
            traced = TraceResult(
                kind: .unavailable,
                exactRevision: nil,
                earliestPositiveRevision: nil,
                reasons: reasons,
                semanticComparisons: comparisons
            )
        }

        return try conclusion(
            finding: finding,
            attempt: attempt,
            evidence: evidence,
            openingSnapshot: openingSnapshot,
            startRecord: startRecord,
            traced: traced
        )
    }

    private func conclusion(
        finding: Finding,
        attempt: UInt,
        evidence: IntroductionHistoryEvidence,
        openingSnapshot: ObservationSnapshot,
        startRecord: IntroductionHistoryRevision,
        traced: TraceResult
    ) throws -> IntroductionConclusion {
        var blockers = try globalBlockers(openingSnapshot: openingSnapshot, evidence: evidence)
        if let startObservation = startRecord.observation,
            sourceDigest(of: startObservation) != sourceDigest(of: openingSnapshot)
        {
            blockers.append(
                try LifecycleReason(
                    code: "opening-source-mismatch",
                    message: "The archived starting revision does not match the First Observation source digest."
                )
            )
        }

        let resultKind: IntroductionConclusionKind
        let exactRevision: GitRevisionID?
        if traced.kind == .exact, !blockers.isEmpty {
            resultKind = .bounded
            exactRevision = nil
        } else {
            resultKind = traced.kind
            exactRevision = traced.exactRevision
        }
        return IntroductionConclusion(
            findingID: finding.id,
            attempt: attempt,
            kind: resultKind,
            exactRevision: exactRevision,
            earliestPositiveRevision: traced.earliestPositiveRevision,
            reasons: unique(traced.reasons + blockers),
            evidence: evidence,
            semanticComparisons: traced.semanticComparisons
        )
    }

    func validate(
        _ conclusion: IntroductionConclusion,
        artifact: LifecycleArtifact
    ) throws {
        guard let finding = artifact.finding(id: conclusion.findingID) else {
            throw LifecycleContractError.invalidArtifact(
                "An Introduction Conclusion references a missing Finding."
            )
        }
        let expected = try make(
            finding: finding,
            attempt: conclusion.attempt,
            evidence: conclusion.evidence,
            artifact: artifact
        )
        guard expected == conclusion else {
            throw LifecycleContractError.invalidArtifact(
                "An Introduction Conclusion does not match its persisted historical evidence."
            )
        }
    }
}

enum RevisionAssessment {
    case present(SemanticComparisonBasis)
    case absent(SemanticComparisonBasis)
    case incomplete([LifecycleReason], semanticComparisons: [SemanticComparisonBasis])
}

struct TraceResult {
    var kind: IntroductionConclusionKind
    var exactRevision: GitRevisionID?
    var earliestPositiveRevision: GitRevisionID?
    var reasons: [LifecycleReason]
    var semanticComparisons: [SemanticComparisonBasis]
}
