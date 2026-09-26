import SwiftDebtCore

extension LegacyIntroductionConclusionEvaluator {
    func assess(
        _ record: IntroductionHistoryRevision,
        openingDetection: ObservedDetection,
        openingSnapshot: ObservationSnapshot,
        rule: SnapshotRule
    ) throws -> LegacyRevisionAssessment {
        if let reason = record.unavailableReason { return .incomplete([reason]) }
        guard let observation = record.observation else {
            return .incomplete([
                try LifecycleReason(
                    code: "history-observation-unavailable",
                    message: "Revision \(record.revision.rawValue) has no historical observation."
                )
            ])
        }
        guard observation.provenance.scope.isCompleteRepository else {
            return .incomplete([
                try LifecycleReason(
                    code: "historical-scope-incomplete",
                    message: "Revision \(record.revision.rawValue) was not analyzed with repository scope."
                )
            ])
        }
        guard
            observation.provenance.configurationFingerprint
                == openingSnapshot.provenance.configurationFingerprint
        else {
            return .incomplete([
                try LifecycleReason(
                    code: "historical-configuration-incomparable",
                    message: "Revision \(record.revision.rawValue) used a different analysis configuration."
                )
            ])
        }
        guard observation.provenance.engineVersion == openingSnapshot.provenance.engineVersion else {
            return .incomplete([
                try LifecycleReason(
                    code: "historical-engine-incomparable",
                    message: "Revision \(record.revision.rawValue) used a different engine version."
                )
            ])
        }
        guard observation.provenance.capabilities == openingSnapshot.provenance.capabilities,
            observation.provenance.capabilities.allSatisfy({ $0.state.supportsComparison })
        else {
            return .incomplete([
                try LifecycleReason(
                    code: "historical-capability-incomparable",
                    message: "Revision \(record.revision.rawValue) lacks comparable analysis capabilities."
                )
            ])
        }
        let atomics = observation.atomicObservations.filter { $0.rule == rule }
        guard atomics.count == observation.sources.count, !atomics.isEmpty,
            atomics.allSatisfy({ $0.outcome.isCommitted })
        else {
            return .incomplete([
                try LifecycleReason(
                    code: "historical-observation-incomplete",
                    message:
                        "Revision \(record.revision.rawValue) lacks committed target-rule evidence for every SourceUnit."
                )
            ])
        }
        guard let anchor = openingDetection.structuralEvidence else {
            return .incomplete([
                try LifecycleReason(
                    code: "opening-structural-evidence-unavailable",
                    message: "The Finding's First Observation lacks engine-owned structural evidence."
                )
            ])
        }

        let detections = observation.detections.filter { $0.rule == rule }
        let exact = detections.filter { $0.structuralEvidence == anchor }
        if exact.count == 1, let detection = exact.first,
            detection.location.sourcePath == openingDetection.location.sourcePath
        {
            return .present
        }
        if !exact.isEmpty {
            return .incomplete([
                try LifecycleReason(
                    code: "historical-cross-file-continuity-unsupported",
                    message:
                        "Revision \(record.revision.rawValue) has exact structural candidates without persisted rename proof."
                )
            ])
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
            return .incomplete([
                try LifecycleReason(
                    code: "historical-continuity-ambiguous",
                    message:
                        "Revision \(record.revision.rawValue) contains a credible but non-unique structural predecessor."
                )
            ])
        }
        return .absent
    }

}
