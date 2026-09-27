import SwiftDebtCore

/// A transient search index. It proposes pairs for the full continuity relation;
/// it never establishes Finding identity on its own.
struct ContinuityCandidateIndex {
    private struct DigestKey: Hashable {
        let algorithm: String
        let digestAlgorithm: String
        let digest: String
    }

    private final class RuleBucket {
        var all: [Int] = []
        var incomplete: [Int] = []
        var byAlgorithm: [String: [Int]] = [:]
        var bySubject: [DigestKey: [Int]] = [:]
        var byDeclaration: [DigestKey: [Int]] = [:]
    }

    private var byRule: [SnapshotRule: RuleBucket] = [:]

    init(detections: [ObservedDetection]) {
        for (index, detection) in detections.enumerated() {
            let bucket = byRule[detection.rule] ?? RuleBucket()
            bucket.all.append(index)
            if let evidence = detection.structuralEvidence,
                let declaration = evidence.enclosingDeclarationDigest
            {
                let algorithm = evidence.algorithm.rawValue
                bucket.byAlgorithm[algorithm, default: []].append(index)
                bucket.bySubject[
                    DigestKey(
                        algorithm: algorithm,
                        digestAlgorithm: evidence.subjectDigest.algorithm.rawValue,
                        digest: evidence.subjectDigest.value
                    ), default: []
                ].append(index)
                bucket.byDeclaration[
                    DigestKey(
                        algorithm: algorithm,
                        digestAlgorithm: declaration.algorithm.rawValue,
                        digest: declaration.value
                    ), default: []
                ].append(index)
            } else {
                bucket.incomplete.append(index)
            }
            byRule[detection.rule] = bucket
        }
    }

    var rules: [SnapshotRule] {
        byRule.keys.sorted {
            if $0.identity != $1.identity { return $0.identity.description < $1.identity.description }
            return $0.semanticRevision.rawValue < $1.semanticRevision.rawValue
        }
    }

    func possibleDetections(
        for candidate: Candidate,
        currentRule: SnapshotRule,
        semanticsCompatible: Bool
    ) -> [Int] {
        guard let bucket = byRule[currentRule] else { return [] }
        guard semanticsCompatible,
            let prior = candidate.detection.structuralEvidence,
            let declaration = prior.enclosingDeclarationDigest
        else { return bucket.all }

        let algorithm = prior.algorithm.rawValue
        var possible = Set(bucket.incomplete)
        for (otherAlgorithm, indices) in bucket.byAlgorithm where otherAlgorithm != algorithm {
            possible.formUnion(indices)
        }
        possible.formUnion(
            bucket.bySubject[
                DigestKey(
                    algorithm: algorithm,
                    digestAlgorithm: prior.subjectDigest.algorithm.rawValue,
                    digest: prior.subjectDigest.value
                )
            ] ?? [])
        possible.formUnion(
            bucket.byDeclaration[
                DigestKey(
                    algorithm: algorithm,
                    digestAlgorithm: declaration.algorithm.rawValue,
                    digest: declaration.value
                )
            ] ?? [])
        return possible.sorted()
    }
}
