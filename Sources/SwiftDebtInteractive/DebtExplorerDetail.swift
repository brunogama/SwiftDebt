import Foundation
import SwiftDebtCore

public struct DebtExplorerDetail: Equatable, Sendable {
    public let title: String
    public let location: String
    public let priority: String
    public let score: String
    public let explanation: String
    public let recommendation: String
    public let scoreExplanation: String
    public let sourceContext: String
    public let editorCommand: String?

    public init(item: RankedDebtItem, editor: String? = nil) {
        title = item.item.entity.displayName
        location = item.item.entity.location.debtExplorerLocation
        priority = item.score.priority?.rawValue ?? "unscored"
        score = item.score.value.debtExplorerScore
        explanation = item.explanation
        recommendation = item.recommendation
        scoreExplanation = Self.scoreExplanation(for: item)
        sourceContext = Self.sourceContext(for: item, scoreExplanation: scoreExplanation)
        editorCommand = Self.editorCommand(for: item.item.entity.location, editor: editor)
    }

    private static func scoreExplanation(for item: RankedDebtItem) -> String {
        var lines: [String] = [
            "Score: \(item.score.value.debtExplorerScore)",
            "Priority: \(item.score.priority?.rawValue ?? "unscored")",
        ]
        if !item.score.breakdown.contributions.isEmpty {
            lines.append("Contributions:")
            for contribution in item.score.breakdown.contributions {
                lines.append(contributionLine(contribution))
            }
        }
        if !item.score.breakdown.unavailableEvidence.isEmpty {
            lines.append("Unavailable evidence:")
            for evidence in item.score.breakdown.unavailableEvidence {
                lines.append("- \(evidence.kind) \(evidence.evidenceID): \(evidence.reason ?? "unspecified")")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func contributionLine(_ contribution: DebtScoreContribution) -> String {
        "- \(contribution.kind) \(contribution.evidenceID): raw=\(contribution.rawValue), normalized=\(contribution.normalizedScore.debtExplorerScore), weight=\(contribution.effectiveWeight.debtExplorerScore), contribution=\(contribution.contribution.debtExplorerScore)"
    }

    private static func sourceContext(for item: RankedDebtItem, scoreExplanation: String) -> String {
        var lines = [
            item.item.entity.location.debtExplorerLocation,
            item.item.entity.displayName,
            "Priority: \(item.score.priority?.rawValue ?? "unscored")",
            "Score: \(item.score.value.debtExplorerScore)",
            "Category: \(item.category)",
            "Why: \(item.explanation)",
            "Action: \(item.recommendation)",
            "Evidence:",
        ]
        for evidence in item.item.evidence {
            let evidenceLocation = evidence.location.map { " @ \($0.debtExplorerLocation)" } ?? ""
            lines.append("- \(evidence.kind): \(evidence.rawValue)\(evidenceLocation)")
        }
        lines.append("Score explanation:")
        lines.append(scoreExplanation)
        return lines.joined(separator: "\n")
    }

    private static func editorCommand(for location: DebtLocation, editor: String?) -> String? {
        guard let editor, !editor.isEmpty, let file = location.file else { return nil }
        let line = location.line ?? 1
        return "\(shellQuote(editor)) +\(line) \(shellQuote(file))"
    }
}

extension DebtLocation {
    var debtExplorerLocation: String {
        let file = file ?? "unknown"
        guard let line else { return file }
        return "\(file):\(line):\(column ?? 1)"
    }
}

extension Optional where Wrapped == Double {
    var debtExplorerScore: String {
        guard let self else { return "N/A" }
        return self.debtExplorerScore
    }
}

extension Double {
    var debtExplorerScore: String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}

private func shellQuote(_ value: String) -> String {
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./+-")
    if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
        return value
    }
    return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
