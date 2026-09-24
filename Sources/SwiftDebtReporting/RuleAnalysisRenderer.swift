import Foundation
import SwiftDebtCore

package struct RuleAnalysisRenderer {
    package init() {}

    package func render(_ snapshot: AnalysisSnapshot) -> String {
        let committedCount = snapshot.ruleResults.count { $0.isCommitted }
        let expectedCount = snapshot.ruleDescriptors.count * snapshot.selectedSourcePaths.count
        var lines = [
            "RULE OBSERVATIONS",
            "Status: \(snapshot.isComplete ? "complete" : "INCOMPLETE")"
                + " | selected rules: \(snapshot.ruleDescriptors.count)"
                + " | selected sources: \(snapshot.selectedSourcePaths.count)"
                + " | committed executions: \(committedCount)/\(expectedCount)"
                + " | detections: \(snapshot.detections.count)",
        ]

        for descriptor in snapshot.ruleDescriptors {
            lines.append(
                "Rule: \(descriptor.identity)@\(descriptor.semanticRevision) | \(singleLine(descriptor.metadata.name))"
                    + " | default severity: \(descriptor.metadata.defaultSeverity.rawValue)"
            )
            let results = snapshot.ruleResults
                .filter { $0.descriptor == descriptor }
                .sorted { $0.sourcePath.rawValue < $1.sourcePath.rawValue }
            for result in results {
                switch result.outcome {
                case .committed(let detections):
                    for detection in detections.sorted(by: detectionOrder) {
                        lines.append(render(detection))
                        if let documentationURL = descriptor.metadata.documentationURL {
                            lines.append("  Why: \(singleLine(descriptor.contract.rationale))")
                            lines.append("  Change: \(singleLine(descriptor.metadata.remediation))")
                            lines.append("  Read: \(singleLine(documentationURL))")
                        }
                    }
                case .parseFailed(let diagnostics):
                    lines += diagnostics.sorted(by: diagnosticOrder).map { diagnostic in
                        "\(result.sourcePath):\(diagnostic.location.line):\(diagnostic.location.column): parse-failed"
                            + " \(diagnostic.severity.rawValue): \(singleLine(diagnostic.message))"
                    }
                case .unsupported(let reason):
                    lines.append("\(result.sourcePath): unsupported: \(singleLine(reason))")
                case .failed(let reason):
                    lines.append("\(result.sourcePath): failed: \(singleLine(reason))")
                }
            }
        }

        if snapshot.isComplete && snapshot.detections.isEmpty {
            lines.append("No detections in committed rule executions.")
        } else if !snapshot.isComplete && snapshot.detections.isEmpty {
            lines.append("Absence was not established for incomplete rule executions.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(_ detection: Detection) -> String {
        "\(detection.location.sourcePath):\(detection.location.line):\(detection.location.column): "
            + "\(detection.severity.rawValue): [\(detection.ruleIdentity)@\(detection.semanticRevision)] "
            + singleLine(detection.message)
    }

    private func detectionOrder(_ lhs: Detection, _ rhs: Detection) -> Bool {
        if lhs.location.sourcePath != rhs.location.sourcePath {
            return lhs.location.sourcePath.rawValue < rhs.location.sourcePath.rawValue
        }
        if lhs.location.line != rhs.location.line { return lhs.location.line < rhs.location.line }
        if lhs.location.column != rhs.location.column { return lhs.location.column < rhs.location.column }
        return lhs.message < rhs.message
    }

    private func diagnosticOrder(_ lhs: AnalysisDiagnostic, _ rhs: AnalysisDiagnostic) -> Bool {
        if lhs.location.line != rhs.location.line { return lhs.location.line < rhs.location.line }
        if lhs.location.column != rhs.location.column { return lhs.location.column < rhs.location.column }
        return lhs.message < rhs.message
    }

    private func singleLine(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
    }
}
