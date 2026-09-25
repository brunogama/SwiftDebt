extension ContinuityReconciler {
    func relation(
        candidate: Candidate,
        detection: ObservedDetection,
        snapshot: ObservationSnapshot
    ) throws -> PairRelation {
        let comparison = try SemanticComparisonEvaluator().assess(
            claim: .continuity,
            priorSnapshot: candidate.snapshot,
            priorRule: candidate.detection.rule,
            currentSnapshot: snapshot,
            currentRule: detection.rule
        )
        guard comparison.isCompatible else {
            return .unverified(comparison.reasons, comparison.basis)
        }
        guard let prior = candidate.detection.structuralEvidence,
            let current = detection.structuralEvidence,
            prior.enclosingDeclarationDigest != nil,
            current.enclosingDeclarationDigest != nil
        else {
            return .ambiguous(
                comparison.reasons + [
                    try relationReason(
                        "continuity-evidence-unavailable",
                        "R1 Detection has no engine-owned structural identity evidence, so no predecessor was selected."
                    )
                ],
                comparison.basis
            )
        }
        guard prior.algorithm == current.algorithm else {
            return .ambiguous(
                comparison.reasons + [
                    try relationReason(
                        "structural-algorithm-incomparable",
                        "The current and prior structural evidence algorithms differ."
                    )
                ],
                comparison.basis
            )
        }
        guard prior == current else {
            let subjectMatches = prior.subjectDigest == current.subjectDigest
            let declarationMatches =
                prior.enclosingDeclarationDigest
                == current.enclosingDeclarationDigest
            guard subjectMatches || declarationMatches else { return .none }
            let code =
                declarationMatches
                ? "subject-changed-within-declaration" : "enclosing-declaration-changed"
            let message =
                declarationMatches
                ? "The enclosing declaration matches, but the detected subject changed."
                : "The detected subject matches, but its enclosing declaration changed."
            var reasons = comparison.reasons + [try relationReason(code, message)]
            if candidate.detection.location.sourcePath != detection.location.sourcePath {
                reasons.append(
                    try relationReason(
                        "cross-file-move-uncorroborated",
                        "A partial structural match crossed SourceUnit paths without sufficient move evidence."
                    ))
            }
            return .ambiguous(reasons, comparison.basis)
        }

        var reasons =
            comparison.reasons + [
                try relationReason(
                    "structural-anchor-match",
                    "The engine-derived normalized subject and enclosing declaration match."
                )
            ]
        let priorLocation = candidate.detection.location
        let currentLocation = detection.location
        if priorLocation.sourcePath == currentLocation.sourcePath {
            if priorLocation.line != currentLocation.line || priorLocation.column != currentLocation.column {
                reasons.append(
                    try relationReason(
                        "source-location-moved",
                        "The matched Detection moved within the same SourceUnit."
                    ))
            }
            return .supported(reasons, comparison.basis)
        }

        guard
            let rename = snapshot.provenance.sourceRenames.first(where: {
                $0.priorSourcePath == priorLocation.sourcePath
                    && $0.currentSourcePath == currentLocation.sourcePath
            })
        else {
            reasons.append(
                try relationReason(
                    "cross-file-move-uncorroborated",
                    "A structural match crossed SourceUnit paths without one direct-parent Git rename edge."
                ))
            return .ambiguous(reasons, comparison.basis)
        }
        reasons.append(
            try relationReason(
                "git-source-rename",
                "Git recorded \(rename.priorSourcePath.rawValue) -> \(rename.currentSourcePath.rawValue) "
                    + "at \(rename.similarityPercentage)% similarity."
            ))
        return .supported(reasons, comparison.basis)
    }

    private func relationReason(_ code: String, _ message: String) throws -> LifecycleReason {
        try LifecycleReason(code: code, message: message)
    }
}
