import SwiftDebtCore

extension ObservationSnapshot {
    public init(
        id: SnapshotID,
        provenance: SnapshotProvenance,
        analysis: AnalysisSnapshot
    ) throws {
        let orderedResults = analysis.ruleResults.sorted { lhs, rhs in
            if lhs.descriptor.identity.description != rhs.descriptor.identity.description {
                return lhs.descriptor.identity.description < rhs.descriptor.identity.description
            }
            if lhs.descriptor.semanticRevision.rawValue != rhs.descriptor.semanticRevision.rawValue {
                return lhs.descriptor.semanticRevision.rawValue < rhs.descriptor.semanticRevision.rawValue
            }
            return lhs.sourcePath.rawValue < rhs.sourcePath.rawValue
        }
        let rules = try analysis.ruleDescriptors.map {
            try SnapshotRule(
                identity: $0.identity,
                semanticRevision: $0.semanticRevision,
                compatibilityDeclarations: $0.contract.compatibilityDeclarations,
                configurationCompatibilityDeclarations: $0.contract.configurationCompatibilityDeclarations
            )
        }

        var observedDetections: [ObservedDetection] = []
        var atomicObservations: [AtomicObservation] = []
        for (atomicIndex, result) in orderedResults.enumerated() {
            let rule = try SnapshotRule(
                identity: result.descriptor.identity,
                semanticRevision: result.descriptor.semanticRevision,
                compatibilityDeclarations: result.descriptor.contract.compatibilityDeclarations,
                configurationCompatibilityDeclarations:
                    result.descriptor.contract.configurationCompatibilityDeclarations
            )
            let atomicID = try AtomicObservationID("\(id.rawValue):atomic:\(atomicIndex)")
            let outcome: AtomicObservationOutcome
            switch result.outcome {
            case .committed(let detections):
                var detectionIDs: [DetectionID] = []
                for detection in detections {
                    let detectionID = try DetectionID("\(id.rawValue):detection:\(observedDetections.count)")
                    detectionIDs.append(detectionID)
                    observedDetections.append(
                        try ObservedDetection(
                            id: detectionID,
                            rule: rule,
                            severity: detection.severity,
                            location: SnapshotLocation(
                                sourcePath: detection.location.sourcePath,
                                line: detection.location.line,
                                column: detection.location.column
                            ),
                            message: detection.message,
                            structuralEvidence: detection.structuralEvidence
                        )
                    )
                }
                outcome = .committed(detectionIDs)
            case .parseFailed:
                outcome = .notExecuted(
                    try LifecycleReason(
                        code: "source-parse-failed",
                        message: "The SourceUnit did not parse, so the rule did not execute."
                    )
                )
            case .unsupported(let reason):
                outcome = .unsupported(try LifecycleReason(code: "rule-unsupported", message: reason))
            case .failed(let reason):
                outcome = .failed(try LifecycleReason(code: "rule-failed", message: reason))
            }
            atomicObservations.append(
                AtomicObservation(id: atomicID, rule: rule, sourcePath: result.sourcePath, outcome: outcome)
            )
        }

        let sources = try analysis.selectedSourcePaths.map { sourcePath in
            let failures = analysis.ruleResults.compactMap { result -> [AnalysisDiagnostic]? in
                guard result.sourcePath == sourcePath else { return nil }
                if case .parseFailed(let diagnostics) = result.outcome { return diagnostics }
                return nil
            }
            if let diagnostics = failures.first {
                guard failures.allSatisfy({ $0 == diagnostics }) else {
                    throw LifecycleContractError.invalidSnapshot(
                        "Parse diagnostics disagree across rules for \(sourcePath.rawValue)."
                    )
                }
                return SourceObservation(sourcePath: sourcePath, parseOutcome: .failed(diagnostics))
            }
            return SourceObservation(sourcePath: sourcePath, parseOutcome: .parsed)
        }

        try self.init(
            id: id,
            provenance: provenance,
            rules: rules,
            sources: sources,
            atomicObservations: atomicObservations,
            detections: observedDetections
        )
    }
}
