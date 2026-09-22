import Foundation
import SwiftDebtCore

let historyKinds = [
    ("change-frequency", "git-history.change-frequency"),
    ("recency", "git-history.recency"),
    ("fix-orientation", "git-history.fix-orientation"),
    ("contributor-concentration", "git-history.contributor-concentration"),
]

func historyEvidence(
    for entity: DebtEntity,
    total: Int,
    latest: Date,
    days: Int,
    fixCount: Int,
    contributorCount: Int,
    topShare: Double,
    referenceTime: Date,
    historyLimit: Int,
    isTruncated: Bool
) -> [DebtEvidence] {
    let reference = iso8601String(referenceTime)
    let latestText = iso8601String(latest)
    return [
        DebtEvidence(
            id: "\(entity.id):git-history:change-frequency",
            kind: "git-history.change-frequency",
            weight: 1,
            normalizedScore: min(100, Double(total) * 20),
            rawValue:
                "commits=\(total);window=last-\(historyLimit)-file-commits;truncated=\(isTruncated)",
            location: entity.location,
            note:
                "Counted a bounded, rename-aware Git history for the entity file; truncation is reported explicitly."
        ),
        DebtEvidence(
            id: "\(entity.id):git-history:recency",
            kind: "git-history.recency",
            weight: 1,
            normalizedScore: min(100, 100 / (1 + Double(days) / 30)),
            rawValue: "lastChangeDaysAgo=\(days);lastChangedAt=\(latestText);referenceTime=\(reference)",
            location: entity.location,
            note: "Computed against the injected reference time, not an ambient clock."
        ),
        DebtEvidence(
            id: "\(entity.id):git-history:fix-orientation",
            kind: "git-history.fix-orientation",
            weight: 1,
            normalizedScore: Double(fixCount) * 100 / Double(total),
            rawValue: "fixCommits=\(fixCount);commits=\(total);rules=fix,bug,crash,defect,regression,hotfix,repair",
            location: entity.location,
            note: "Fix-oriented commits are classified by subject tokens only."
        ),
        DebtEvidence(
            id: "\(entity.id):git-history:contributor-concentration",
            kind: "git-history.contributor-concentration",
            weight: 1,
            normalizedScore: topShare * 100,
            rawValue: "uniqueContributors=\(contributorCount);topShare=\(format(topShare))",
            location: entity.location,
            note: "Contributor identities are counted internally and omitted from evidence output."
        ),
    ]
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
    case let (.some(left), .some(right)): left == right ? nil : left < right
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
