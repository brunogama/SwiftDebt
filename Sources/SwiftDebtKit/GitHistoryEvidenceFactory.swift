import Foundation
import SwiftDebtCore

let historyKinds = [
    ("change-frequency", "git-history.change-frequency"),
    ("recency", "git-history.recency"),
    ("fix-orientation", "git-history.fix-orientation"),
    ("contributor-concentration", "git-history.contributor-concentration"),
]

struct GitHistoryEvidenceInput {
    let entity: DebtEntity
    let total: Int
    let latest: Date
    let days: Int
    let fixCount: Int
    let contributorCount: Int
    let topShare: Double
    let referenceTime: Date
    let historyLimit: Int
    let isTruncated: Bool
}

func historyEvidence(_ input: GitHistoryEvidenceInput) -> [DebtEvidence] {
    let reference = iso8601String(input.referenceTime)
    let latestText = iso8601String(input.latest)
    return [
        changeFrequencyEvidence(input),
        recencyEvidence(input, latestText: latestText, reference: reference),
        fixOrientationEvidence(input),
        contributorConcentrationEvidence(input),
    ]
}

private func changeFrequencyEvidence(_ input: GitHistoryEvidenceInput) -> DebtEvidence {
    DebtEvidence(
        id: "\(input.entity.id):git-history:change-frequency",
        kind: "git-history.change-frequency",
        weight: 1,
        normalizedScore: min(100, Double(input.total) * 20),
        rawValue:
            "commits=\(input.total);window=last-\(input.historyLimit)-file-commits;truncated=\(input.isTruncated)",
        location: input.entity.location,
        note:
            "Counted a bounded, rename-aware Git history for the entity file; truncation is "
            + "reported explicitly."
    )
}

private func recencyEvidence(
    _ input: GitHistoryEvidenceInput, latestText: String, reference: String
) -> DebtEvidence {
    DebtEvidence(
        id: "\(input.entity.id):git-history:recency",
        kind: "git-history.recency",
        weight: 1,
        normalizedScore: min(100, 100 / (1 + Double(input.days) / 30)),
        rawValue:
            "lastChangeDaysAgo=\(input.days);lastChangedAt=\(latestText);referenceTime=\(reference)",
        location: input.entity.location,
        note: "Computed against the injected reference time, not an ambient clock."
    )
}

private func fixOrientationEvidence(_ input: GitHistoryEvidenceInput) -> DebtEvidence {
    DebtEvidence(
        id: "\(input.entity.id):git-history:fix-orientation",
        kind: "git-history.fix-orientation",
        weight: 1,
        normalizedScore: Double(input.fixCount) * 100 / Double(input.total),
        rawValue:
            "fixCommits=\(input.fixCount);commits=\(input.total);rules=fix,bug,crash,defect,regression,hotfix,repair",
        location: input.entity.location,
        note: "Fix-oriented commits are classified by subject tokens only."
    )
}

private func contributorConcentrationEvidence(_ input: GitHistoryEvidenceInput) -> DebtEvidence {
    DebtEvidence(
        id: "\(input.entity.id):git-history:contributor-concentration",
        kind: "git-history.contributor-concentration",
        weight: 1,
        normalizedScore: input.topShare * 100,
        rawValue:
            "uniqueContributors=\(input.contributorCount);topShare=\(format(input.topShare))",
        location: input.entity.location,
        note: "Contributor identities are counted internally and omitted from evidence output."
    )
}

func unavailableEvidence(for entity: DebtEntity, reason: String) -> [DebtEvidence] {
    historyKinds.map { suffix, kind in
        DebtEvidence(
            id: "\(entity.id):git-history:\(suffix)",
            kind: kind,
            availability: .unavailable(reason: reason),
            weight: 1,
            normalizedScore: nil,
            rawValue: "unavailable",
            location: entity.location,
            note: "Git history evidence unavailable; no zero-valued risk was fabricated."
        )
    }
}

func entityOrder(_ lhs: DebtEntity, _ rhs: DebtEntity) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
    if lhs.level.rawValue != rhs.level.rawValue { return lhs.level.rawValue < rhs.level.rawValue }
    return locationOrder(lhs.location, rhs.location)
}

func locationOrder(_ lhs: DebtLocation, _ rhs: DebtLocation) -> Bool {
    if let ordered = ordered(lhs.module, rhs.module) { return ordered }
    if let ordered = ordered(lhs.file, rhs.file) { return ordered }
    if let ordered = ordered(lhs.line, rhs.line) { return ordered }
    if let ordered = ordered(lhs.column, rhs.column) { return ordered }
    return false
}

func evidenceOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
    if lhs.id != rhs.id { return lhs.id < rhs.id }
    if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
    return lhs.rawValue < rhs.rawValue
}

func commitOrder(_ lhs: GitCommitRecord, _ rhs: GitCommitRecord) -> Bool {
    if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
    return lhs.sha < rhs.sha
}

func ordered<T: Comparable>(_ lhs: T?, _ rhs: T?) -> Bool? {
    switch (lhs, rhs) {
    case (.none, .none): nil
    case (.none, .some): true
    case (.some, .none): false
    case (.some(let left), .some(let right)): left == right ? nil : left < right
    }
}

func iso8601String(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

func format(_ value: Double) -> String {
    String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
}
