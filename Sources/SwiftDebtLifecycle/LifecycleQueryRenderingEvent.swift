extension LifecycleReadService {
    func renderEvent(_ event: LifecycleEvent) -> [String] {
        let basis = event.basisEventIDs.map { oneLine($0.rawValue) }.joined(separator: ", ")
        var lines = [
            "Event \(oneLine(event.id.rawValue)) snapshot=\(oneLine(event.snapshotID.rawValue)) "
                + "\(event.transition.kind.rawValue) contract=\(event.evidenceContract.rawValue)",
            "  Basis Events: \(basis.isEmpty ? "none" : basis)",
        ]
        let reasons: [LifecycleReason]
        switch event.transition {
        case .opened(let evidence):
            lines.append(renderDetectionReference(evidence, label: "Detection"))
            reasons = []
        case .observed(let evidence), .reopened(let evidence):
            lines.append(renderDetectionReference(evidence.currentDetection, label: "Current Detection"))
            lines.append(
                "  Prior Detection: \(oneLine(evidence.priorSnapshotID.rawValue)) "
                    + oneLine(evidence.priorDetectionID.rawValue)
            )
            reasons = evidence.reasons
        case .resolved(let evidence):
            lines.append("  Prior Snapshot: \(oneLine(evidence.priorSnapshotID.rawValue))")
            let covered = evidence.coveredAtomicObservationIDs.map { oneLine($0.rawValue) }
                .joined(separator: ", ")
            lines.append("  Covered Atomic Observations: \(covered)")
            reasons = evidence.reasons
        case .unverified(let blockers):
            reasons = blockers
        case .continuityAmbiguous(let evidence):
            let detections = evidence.currentDetectionIDs.map { oneLine($0.rawValue) }
                .joined(separator: ", ")
            let candidates = evidence.candidateFindingIDs.map { oneLine($0.rawValue) }
                .joined(separator: ", ")
            lines.append("  Current Detection IDs: \(detections)")
            lines.append("  Candidate Findings: \(candidates)")
            reasons = evidence.reasons
        }
        lines += reasons.map { "  \(oneLine($0.code)): \(oneLine($0.message))" }
        return lines
    }

    private func renderDetectionReference(_ evidence: DetectionEvidence, label: String) -> String {
        "  \(label): \(oneLine(evidence.detectionID.rawValue)) "
            + "atomic=\(oneLine(evidence.atomicObservationID.rawValue))"
    }
}
