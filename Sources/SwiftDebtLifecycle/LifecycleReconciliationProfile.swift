import SwiftDebtCore

/// Optional operational measurements for one processed snapshot. These values are not lifecycle evidence.
public struct LifecycleReconciliationProfile: Codable, Equatable, Sendable {
    public let snapshotID: SnapshotID
    /// All current Detections in this snapshot.
    public let detections: Int
    /// Prior Findings considered across the snapshot's Rule Identities.
    public let candidates: Int
    /// Distinct Candidate-Detection pairs assessed by the continuity relation
    /// or retained by the same-source divergence rule.
    public let evaluatedPairs: Int
    /// Credible relation edges after same-source divergence augmentation.
    public let crediblePairs: Int
    public let uniqueContinuities: Int
    public let newFindings: Int
    public let unresolvedDetections: Int
    public let ambiguousGroups: Int
    /// Rule processing, including reconciliation and lifecycle event application.
    public let processingElapsedNanoseconds: UInt64
    /// Time spent in the continuity reconciler, excluding persistence and artifact validation.
    public let reconciliationElapsedNanoseconds: UInt64

    package init(
        snapshotID: SnapshotID,
        detections: Int,
        candidates: Int,
        evaluatedPairs: Int,
        crediblePairs: Int,
        uniqueContinuities: Int,
        newFindings: Int,
        unresolvedDetections: Int,
        ambiguousGroups: Int,
        processingElapsedNanoseconds: UInt64,
        reconciliationElapsedNanoseconds: UInt64
    ) {
        self.snapshotID = snapshotID
        self.detections = detections
        self.candidates = candidates
        self.evaluatedPairs = evaluatedPairs
        self.crediblePairs = crediblePairs
        self.uniqueContinuities = uniqueContinuities
        self.newFindings = newFindings
        self.unresolvedDetections = unresolvedDetections
        self.ambiguousGroups = ambiguousGroups
        self.processingElapsedNanoseconds = processingElapsedNanoseconds
        self.reconciliationElapsedNanoseconds = reconciliationElapsedNanoseconds
    }
}
