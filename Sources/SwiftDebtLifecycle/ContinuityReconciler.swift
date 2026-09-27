import SwiftDebtCore

struct ContinuityMatch {
    let finding: Finding
    let priorSnapshot: ObservationSnapshot
    let priorDetection: ObservedDetection
    let currentDetection: ObservedDetection
    let reasons: [LifecycleReason]
    let semanticComparison: SemanticComparisonBasis
}

struct ContinuityUnresolvedGroup {
    let findings: [Finding]
    let detections: [ObservedDetection]
    let reasons: [LifecycleReason]
    let semanticComparisons: [SemanticComparisonBasis]
    let isAmbiguous: Bool
}

struct ContinuityReconciliation {
    let matches: [ContinuityMatch]
    let unresolvedGroups: [ContinuityUnresolvedGroup]
    let newDetections: [ObservedDetection]
    let absentFindings: [Finding]
    let evaluatedPairs: Int
    let crediblePairs: Int
}

struct ContinuityReconciler {
    func reconcile(
        findings: [Finding],
        detections: [ObservedDetection],
        snapshot: ObservationSnapshot,
        artifact: LifecycleArtifact
    ) throws -> ContinuityReconciliation {
        let snapshotsByID = Dictionary(uniqueKeysWithValues: artifact.snapshots.map { ($0.id, $0) })
        var detectionIndexBySnapshot: [SnapshotID: [DetectionID: ObservedDetection]] = [:]
        let candidates = try findings.map { finding -> Candidate in
            let reference = finding.latestDetectionReference
            guard let priorSnapshot = snapshotsByID[reference.snapshotID] else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) has no latest Detection evidence."
                )
            }
            if detectionIndexBySnapshot[reference.snapshotID] == nil {
                detectionIndexBySnapshot[reference.snapshotID] = Dictionary(
                    uniqueKeysWithValues: priorSnapshot.detections.map { ($0.id, $0) }
                )
            }
            guard let priorDetection = detectionIndexBySnapshot[reference.snapshotID]?[reference.detectionID]
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Finding \(finding.id) has no latest Detection evidence."
                )
            }
            return Candidate(finding: finding, snapshot: priorSnapshot, detection: priorDetection)
        }

        var relations: [Pair: PairRelation] = [:]
        var candidateEdges = Array(repeating: Set<Int>(), count: candidates.count)
        var detectionEdges = Array(repeating: Set<Int>(), count: detections.count)
        let index = ContinuityCandidateIndex(detections: detections)
        let currentRules = index.rules
        var evaluatedPairs: Set<Pair> = []
        for candidateIndex in candidates.indices {
            let candidate = candidates[candidateIndex]
            for currentRule in currentRules {
                let comparison = try SemanticComparisonEvaluator().assess(
                    claim: .continuity,
                    priorSnapshot: candidate.snapshot,
                    priorRule: candidate.detection.rule,
                    currentSnapshot: snapshot,
                    currentRule: currentRule
                )
                let possible = index.possibleDetections(
                    for: candidate,
                    currentRule: currentRule,
                    semanticsCompatible: comparison.isCompatible
                )
                for detectionIndex in possible {
                    let pair = Pair(candidate: candidateIndex, detection: detectionIndex)
                    evaluatedPairs.insert(pair)
                    let relation = try relation(
                        candidate: candidate,
                        detection: detections[detectionIndex],
                        snapshot: snapshot,
                        comparison: comparison
                    )
                    guard relation.isCredible else { continue }
                    relations[pair] = relation
                    candidateEdges[candidateIndex].insert(detectionIndex)
                    detectionEdges[detectionIndex].insert(candidateIndex)
                }
            }
        }
        try addSameSourceDivergenceCandidates(
            candidates: candidates,
            detections: detections,
            snapshot: snapshot,
            relations: &relations,
            candidateEdges: &candidateEdges,
            detectionEdges: &detectionEdges,
            evaluatedPairs: &evaluatedPairs
        )

        var matchedCandidates = Set<Int>()
        var matchedDetections = Set<Int>()
        var matches: [ContinuityMatch] = []
        for pair in relations.keys.sorted() {
            guard case .supported(let reasons, let semanticComparison) = relations[pair],
                candidateEdges[pair.candidate].count == 1,
                detectionEdges[pair.detection].count == 1
            else { continue }
            let candidate = candidates[pair.candidate]
            matches.append(
                ContinuityMatch(
                    finding: candidate.finding,
                    priorSnapshot: candidate.snapshot,
                    priorDetection: candidate.detection,
                    currentDetection: detections[pair.detection],
                    reasons: reasons,
                    semanticComparison: semanticComparison
                )
            )
            matchedCandidates.insert(pair.candidate)
            matchedDetections.insert(pair.detection)
        }

        let groups = try unresolvedGroups(
            candidates: candidates,
            detections: detections,
            relations: relations,
            candidateEdges: candidateEdges,
            detectionEdges: detectionEdges,
            excludingCandidates: matchedCandidates,
            excludingDetections: matchedDetections
        )
        let groupedCandidates = Set(
            groups.flatMap { group in
                group.findings.compactMap { finding in candidates.firstIndex { $0.finding.id == finding.id } }
            })
        let groupedDetections = Set(
            groups.flatMap { group in
                group.detections.compactMap { detection in detections.firstIndex { $0.id == detection.id } }
            })

        return ContinuityReconciliation(
            matches: matches.sorted { $0.finding.id.rawValue < $1.finding.id.rawValue },
            unresolvedGroups: groups,
            newDetections: detections.indices.compactMap { index in
                matchedDetections.contains(index) || groupedDetections.contains(index) ? nil : detections[index]
            },
            absentFindings: candidates.indices.compactMap { index in
                matchedCandidates.contains(index) || groupedCandidates.contains(index)
                    ? nil : candidates[index].finding
            },
            evaluatedPairs: evaluatedPairs.count,
            crediblePairs: relations.count
        )
    }

}

struct Candidate {
    let finding: Finding
    let snapshot: ObservationSnapshot
    let detection: ObservedDetection
}

struct Pair: Hashable, Comparable {
    let candidate: Int
    let detection: Int

    static func < (lhs: Pair, rhs: Pair) -> Bool {
        lhs.candidate == rhs.candidate
            ? lhs.detection < rhs.detection : lhs.candidate < rhs.candidate
    }
}

enum PairRelation {
    case none
    case supported([LifecycleReason], SemanticComparisonBasis)
    case ambiguous([LifecycleReason], SemanticComparisonBasis)
    case unverified([LifecycleReason], SemanticComparisonBasis)

    var isCredible: Bool {
        if case .none = self { return false }
        return true
    }

    var reasons: [LifecycleReason] {
        switch self {
        case .none: []
        case .supported(let reasons, _), .ambiguous(let reasons, _), .unverified(let reasons, _): reasons
        }
    }

    var semanticComparison: SemanticComparisonBasis {
        switch self {
        case .supported(_, let basis), .ambiguous(_, let basis), .unverified(_, let basis): basis
        case .none: preconditionFailure("A non-credible relation has no Semantic Comparison Basis.")
        }
    }

    var isAmbiguous: Bool {
        switch self {
        case .supported, .ambiguous: true
        case .none, .unverified: false
        }
    }
}
