extension ContinuityReconciler {
    func relation(
        candidate: Candidate,
        detection: ObservedDetection,
        snapshot: ObservationSnapshot
    ) throws -> PairRelation {
        guard candidate.detection.rule.semanticRevision == detection.rule.semanticRevision else {
            return .unverified([
                try relationReason(
                    "semantic-revision-incomparable",
                    "The current and prior Semantic Revisions have no compatibility declaration."
                )
            ])
        }
        guard
            candidate.snapshot.provenance.configurationFingerprint
                == snapshot.provenance.configurationFingerprint
        else {
            return .unverified([
                try relationReason(
                    "configuration-incomparable",
                    "The current and prior effective configuration fingerprints differ."
                )
            ])
        }
        guard candidate.snapshot.provenance.sourceIdentity.supportsComparison,
            snapshot.provenance.sourceIdentity.supportsComparison
        else {
            return .unverified([
                try relationReason(
                    "source-identity-unavailable",
                    "Both observations require comparable source identity."
                )
            ])
        }
        guard capabilitiesComparable(candidate.snapshot, snapshot) else {
            return .unverified([
                try relationReason(
                    "capability-incomparable",
                    "The current and prior capability availability differs or is unavailable."
                )
            ])
        }
        guard let prior = candidate.detection.structuralEvidence,
            let current = detection.structuralEvidence,
            prior.enclosingDeclarationDigest != nil,
            current.enclosingDeclarationDigest != nil
        else {
            return .ambiguous([
                try relationReason(
                    "continuity-evidence-unavailable",
                    "R1 Detection has no engine-owned structural identity evidence, so no predecessor was selected."
                )
            ])
        }
        guard prior.algorithm == current.algorithm else {
            return .ambiguous([
                try relationReason(
                    "structural-algorithm-incomparable",
                    "The current and prior structural evidence algorithms differ."
                )
            ])
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
            var reasons = [try relationReason(code, message)]
            if candidate.detection.location.sourcePath != detection.location.sourcePath {
                reasons.append(
                    try relationReason(
                        "cross-file-move-uncorroborated",
                        "A partial structural match crossed SourceUnit paths without sufficient move evidence."
                    ))
            }
            return .ambiguous(reasons)
        }

        var reasons = [
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
            return .supported(reasons)
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
            return .ambiguous(reasons)
        }
        reasons.append(
            try relationReason(
                "git-source-rename",
                "Git recorded \(rename.priorSourcePath.rawValue) -> \(rename.currentSourcePath.rawValue) "
                    + "at \(rename.similarityPercentage)% similarity."
            ))
        return .supported(reasons)
    }

    private func capabilitiesComparable(
        _ lhs: ObservationSnapshot,
        _ rhs: ObservationSnapshot
    ) -> Bool {
        guard lhs.provenance.capabilities == rhs.provenance.capabilities else { return false }
        return lhs.provenance.capabilities.allSatisfy { capability in
            if case .available = capability.state { return true }
            return false
        }
    }

    private func relationReason(_ code: String, _ message: String) throws -> LifecycleReason {
        try LifecycleReason(code: code, message: message)
    }
}
