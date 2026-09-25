import Foundation
import SwiftDebtCore

public struct RepositoryEvidenceRenderer: Sendable {
    public init() {}

    public func json(_ report: RepositoryEvidenceReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self) + "\n"
    }

    public func text(_ report: RepositoryEvidenceReport) -> String {
        var lines = [
            "REPOSITORY EVIDENCE (EXPERIMENTAL)",
            "Status: \(report.isComplete ? "complete" : "INCOMPLETE")"
                + " | rules: \(report.rules.count)"
                + " | files: \(report.summary.sourceFileCount)"
                + " | detections: \(report.summary.detectionCount)",
            "Snapshot: sha256:\(report.snapshot.contentDigest.value)",
            report.summary.currentSnapshotNotice,
        ]
        for rule in report.rules {
            lines += render(rule)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func render(_ rule: RepositoryRuleEvidence) -> [String] {
        var lines = [
            "Rule: \(rule.ruleIdentity)@\(rule.semanticRevision) | \(singleLine(rule.name))"
                + " | qualification: \(rule.qualification.rawValue)"
                + " | outcome: \(rule.completionState.rawValue)"
        ]
        for issue in rule.issues {
            lines.append("  Incomplete [\(singleLine(issue.code))]: \(singleLine(issue.message))")
        }
        for capability in rule.capabilities {
            lines.append(
                "  Capability [\(singleLine(capability.capability))]: \(capability.state.rawValue)"
                    + " via \(singleLine(capability.provider.name))"
                    + " \(singleLine(capability.provider.version))"
            )
        }
        for detection in rule.detections {
            lines += render(detection)
        }
        if rule.detections.isEmpty {
            if rule.provesAbsence {
                lines.append("  No Detections in the rule's declared observable scope.")
            } else {
                lines.append("  Absence was not established for this incomplete rule outcome.")
            }
        }
        return lines
    }

    private func render(_ detection: RepositoryDetection) -> [String] {
        var lines = [
            "\(location(detection.primaryLocation)): warning: "
                + "[\(detection.selector.ruleIdentity)@\(detection.selector.semanticRevision)] "
                + singleLine(detection.summary),
            "  Predicate: \(singleLine(detection.explanation.predicate))",
        ]
        for fact in detection.explanation.decisiveFacts {
            lines.append(
                "  Evidence [\(fact.evidenceClass.rawValue)/\(singleLine(fact.kind))]: \(singleLine(fact.value))"
            )
        }
        lines.append("  Compared units:")
        for unit in detection.explanation.comparedUnits {
            lines.append(
                "    - \(unit.kind.rawValue) \(singleLine(unit.displayName)) at \(location(unit.location))"
            )
        }
        for limitation in detection.explanation.limitations {
            lines.append("  Limitation: \(singleLine(limitation))")
        }
        lines.append("  Change: \(singleLine(detection.explanation.refactoringDirection))")
        lines.append("  Read: \(singleLine(detection.explanation.documentationURL))")
        return lines
    }

    private func location(_ location: SourceLocation) -> String {
        "\(singleLine(location.file)):\(location.line):\(location.column)"
    }

    private func singleLine(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
    }
}
