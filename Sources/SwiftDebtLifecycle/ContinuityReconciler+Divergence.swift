extension ContinuityReconciler {
    /// A SourceUnit path is insufficient to prove continuity. When neither side
    /// has any structural edge, however, a same-source edit is enough to keep a
    /// possible predecessor unresolved instead of fabricating a split.
    func addSameSourceDivergenceCandidates(
        candidates: [Candidate],
        detections: [ObservedDetection],
        snapshot: ObservationSnapshot,
        relations: inout [Pair: PairRelation],
        candidateEdges: inout [Set<Int>],
        detectionEdges: inout [Set<Int>],
        evaluatedPairs: inout Set<Pair>
    ) throws {
        let disconnectedCandidates = candidateEdges.indices.filter { candidateEdges[$0].isEmpty }
        let disconnectedDetections = detectionEdges.indices.filter { detectionEdges[$0].isEmpty }
        let detectionsByPath = Dictionary(grouping: disconnectedDetections) {
            detections[$0].location.sourcePath
        }
        for candidateIndex in disconnectedCandidates {
            let sourcePath = candidates[candidateIndex].detection.location.sourcePath
            for detectionIndex in detectionsByPath[sourcePath] ?? [] {
                let pair = Pair(candidate: candidateIndex, detection: detectionIndex)
                evaluatedPairs.insert(pair)
                let comparison = try SemanticComparisonEvaluator().assess(
                    claim: .continuity,
                    priorSnapshot: candidates[candidateIndex].snapshot,
                    priorRule: candidates[candidateIndex].detection.rule,
                    currentSnapshot: snapshot,
                    currentRule: detections[detectionIndex].rule
                )
                relations[pair] = .ambiguous(
                    comparison.reasons + [
                        try LifecycleReason(
                            code: "same-source-structural-divergence",
                            message:
                                "Both structural digests changed within the same SourceUnit, so an edited occurrence cannot be ruled out."
                        )
                    ],
                    comparison.basis
                )
                candidateEdges[candidateIndex].insert(detectionIndex)
                detectionEdges[detectionIndex].insert(candidateIndex)
            }
        }
    }
}
