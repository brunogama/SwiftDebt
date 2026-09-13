import Foundation
import SCMACore

struct DebtValidationOutcome {
    let exitStatus: Int32
    let summary: String

    init(analysis: RankedDebtAnalysis?, validation: DebtValidationOptions) {
        guard let analysis else {
            exitStatus = 2
            summary = "Debt validation failed: ranked debt analysis was not produced.\n"
            return
        }
        let scored = analysis.items.compactMap { item -> (id: String, score: Double)? in
            guard let value = item.score.value else { return nil }
            return (item.item.id, value)
        }
        let worst = scored.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.id > rhs.id
        }
        let failing = scored.filter { $0.score > validation.maxScore }.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.id < rhs.id
        }
        exitStatus = failing.isEmpty ? 0 : 1
        let threshold = Self.format(validation.maxScore)
        let worstText = worst.map { "\($0.id) \(Self.format($0.score))" } ?? "none"
        if failing.isEmpty {
            summary = "Debt validation passed: max-score \(threshold); worst \(worstText).\n"
        } else {
            summary = "Debt validation failed: max-score \(threshold); worst \(worstText); failures \(failing.count).\n"
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
