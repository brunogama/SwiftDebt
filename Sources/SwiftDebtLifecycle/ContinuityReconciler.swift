import SwiftDebtCore

struct ContinuityMatch {
    let finding: Finding
    let priorSnapshot: ObservationSnapshot
    let priorDetection: ObservedDetection
    let currentDetection: ObservedDetection
    let reasons: [LifecycleReason]
}

struct ContinuityUnresolvedGroup {
    let findings: [Finding]
    let detections: [ObservedDetection]
    let reasons: [LifecycleReason]
    let isAmbiguous: Bool
}

struct ContinuityReconciliation {
    let matches: [ContinuityMatch]
    let unresolvedGroups: [ContinuityUnresolvedGroup]
    let newDetections: [ObservedDetection]
    let absentFindings: [Finding]
}

struct ContinuityReconciler {
    func reconcile(
        findings: [Finding],
        detections: [ObservedDetection],
        snapshot: ObservationSnapshot,
        artifact: LifecycleArtifact
    ) throws -> ContinuityReconciliation {
        let candidates = try findings.map { finding -> Candidate in
            let reference = finding.latestDetectionReference
            guard let priorSnapshot = artifact.snapshot(id: reference.snapshotID),
                let priorDetection = priorSnapshot.detection(id: reference.detectionID)
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
        for candidateIndex in candidates.indices {
            for detectionIndex in detections.indices {
                let relation = try relation(
                    candidate: candidates[candidateIndex],
                    detection: detections[detectionIndex],
                    snapshot: snapshot
                )
                guard relation.isCredible else { continue }
                let pair = Pair(candidate: candidateIndex, detection: detectionIndex)
                relations[pair] = relation
                candidateEdges[candidateIndex].insert(detectionIndex)
                detectionEdges[detectionIndex].insert(candidateIndex)
            }
        }
        try addSameSourceDivergenceCandidates(
            candidates: candidates,
            detections: detections,
            relations: &relations,
            candidateEdges: &candidateEdges,
            detectionEdges: &detectionEdges
        )

        var matchedCandidates = Set<Int>()
        var matchedDetections = Set<Int>()
        var matches: [ContinuityMatch] = []
        for pair in relations.keys.sorted() {
            guard case .supported(let reasons) = relations[pair],
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
                    reasons: reasons
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
            }
        )
    }

    /// A SourceUnit path is insufficient to prove continuity. When neither side
    /// has any structural edge, however, a same-source edit is enough to keep a
    /// possible predecessor unresolved instead of fabricating a split.
    private func addSameSourceDivergenceCandidates(
        candidates: [Candidate],
        detections: [ObservedDetection],
        relations: inout [Pair: PairRelation],
        candidateEdges: inout [Set<Int>],
        detectionEdges: inout [Set<Int>]
    ) throws {
        let disconnectedCandidates = candidateEdges.indices.filter { candidateEdges[$0].isEmpty }
        let disconnectedDetections = detectionEdges.indices.filter { detectionEdges[$0].isEmpty }
        for candidateIndex in disconnectedCandidates {
            for detectionIndex in disconnectedDetections
            where candidates[candidateIndex].detection.location.sourcePath
                == detections[detectionIndex].location.sourcePath
            {
                let pair = Pair(candidate: candidateIndex, detection: detectionIndex)
                relations[pair] = .ambiguous([
                    try reason(
                        "same-source-structural-divergence",
                        "Both structural digests changed within the same SourceUnit, so an edited occurrence cannot be ruled out."
                    )
                ])
                candidateEdges[candidateIndex].insert(detectionIndex)
                detectionEdges[detectionIndex].insert(candidateIndex)
            }
        }
    }

    private func reason(_ code: String, _ message: String) throws -> LifecycleReason {
        try LifecycleReason(code: code, message: message)
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
    case supported([LifecycleReason])
    case ambiguous([LifecycleReason])
    case unverified([LifecycleReason])

    var isCredible: Bool {
        if case .none = self { return false }
        return true
    }

    var reasons: [LifecycleReason] {
        switch self {
        case .none: []
        case .supported(let reasons), .ambiguous(let reasons), .unverified(let reasons): reasons
        }
    }

    var isAmbiguous: Bool {
        switch self {
        case .supported, .ambiguous: true
        case .none, .unverified: false
        }
    }
}
