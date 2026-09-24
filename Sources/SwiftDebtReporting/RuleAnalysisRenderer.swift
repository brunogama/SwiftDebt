import Foundation
import SwiftDebtCore

package struct RuleAnalysisRenderer {
    package init() {}

    package func render(_ snapshot: AnalysisSnapshot) -> String {
        let descriptor = snapshot.ruleDescriptor
        let results = snapshot.ruleResults.sorted { $0.sourcePath.rawValue < $1.sourcePath.rawValue }
        let committedCount = results.count { $0.isCommitted }
        var lines = [
            "RULE OBSERVATIONS",
            "Rule: \(descriptor.identity)@\(descriptor.semanticRevision) | \(singleLine(descriptor.metadata.name))"
                + " | default severity: \(descriptor.metadata.defaultSeverity.rawValue)",
            "Status: \(snapshot.isComplete ? "complete" : "INCOMPLETE")"
                + " | selected sources: \(snapshot.selectedSourcePaths.count)"
                + " | committed sources: \(committedCount)"
                + " | detections: \(snapshot.detections.count)",
        ]

        for result in results {
            switch result.outcome {
            case .committed(let detections):
                lines += detections.sorted(by: detectionOrder).map {
                    render($0, descriptor: result.descriptor)
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

        if snapshot.isComplete && snapshot.detections.isEmpty {
            lines.append("No detections in committed sources.")
        } else if !snapshot.isComplete && snapshot.detections.isEmpty {
            lines.append("Absence was not established for incomplete sources.")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(_ detection: Detection, descriptor: RuleDescriptor) -> String {
        "\(detection.location.sourcePath):\(detection.location.line):\(detection.location.column): "
            + "\(detection.severity.rawValue): [\(descriptor.identity)@\(descriptor.semanticRevision)] "
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
