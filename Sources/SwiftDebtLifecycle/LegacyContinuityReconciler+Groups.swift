extension LegacyContinuityReconciler {
    func unresolvedGroups(
        candidates: [LegacyCandidate],
        detections: [ObservedDetection],
        relations: [LegacyPair: LegacyPairRelation],
        candidateEdges: [Set<Int>],
        detectionEdges: [Set<Int>],
        excludingCandidates: Set<Int>,
        excludingDetections: Set<Int>
    ) throws -> [LegacyContinuityUnresolvedGroup] {
        var visitedCandidates = excludingCandidates
        var visitedDetections = excludingDetections
        var groups: [LegacyContinuityUnresolvedGroup] = []

        for start in candidates.indices where !visitedCandidates.contains(start) && !candidateEdges[start].isEmpty {
            var candidateQueue = [start]
            var detectionQueue: [Int] = []
            var componentCandidates = Set<Int>()
            var componentDetections = Set<Int>()
            while !candidateQueue.isEmpty || !detectionQueue.isEmpty {
                while let candidate = candidateQueue.popLast() {
                    guard visitedCandidates.insert(candidate).inserted else { continue }
                    componentCandidates.insert(candidate)
                    for detection in candidateEdges[candidate] where !excludingDetections.contains(detection) {
                        detectionQueue.append(detection)
                    }
                }
                while let detection = detectionQueue.popLast() {
                    guard visitedDetections.insert(detection).inserted else { continue }
                    componentDetections.insert(detection)
                    for candidate in detectionEdges[detection] where !excludingCandidates.contains(candidate) {
                        candidateQueue.append(candidate)
                    }
                }
            }

            let pairs = relations.filter {
                componentCandidates.contains($0.key.candidate)
                    && componentDetections.contains($0.key.detection)
            }
            var reasons = Set(pairs.values.flatMap(\.reasons))
            let cardinalityAmbiguous =
                pairs.values.contains(where: \.isAmbiguous)
                && (componentCandidates.count > 1 || componentDetections.count > 1)
            if cardinalityAmbiguous {
                reasons.insert(
                    try LifecycleReason(
                        code: "structural-assignment-not-unique",
                        message: "Structural evidence supports more than one predecessor or successor assignment."
                    )
                )
            }
            groups.append(
                LegacyContinuityUnresolvedGroup(
                    findings: componentCandidates.map { candidates[$0].finding }.sorted {
                        $0.id.rawValue < $1.id.rawValue
                    },
                    detections: componentDetections.map { detections[$0] }.sorted {
                        $0.id.rawValue < $1.id.rawValue
                    },
                    reasons: reasons.sorted(by: lifecycleReasonOrder),
                    isAmbiguous: pairs.values.contains(where: \.isAmbiguous)
                )
            )
        }
        return groups.sorted {
            let left = $0.findings.first?.id.rawValue ?? ""
            let right = $1.findings.first?.id.rawValue ?? ""
            return left < right
        }
    }
}
