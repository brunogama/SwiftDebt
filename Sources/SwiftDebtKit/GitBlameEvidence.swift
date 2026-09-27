import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle

struct GitBlameSourceFacts: Equatable, Sendable {
    let sourcePath: SourcePath
    let headRevision: GitRevisionID
    let sourceDigest: LifecycleDigest
    private let revisionsByLine: [GitRevisionID]

    init(
        sourcePath: SourcePath,
        headRevision: GitRevisionID,
        sourceContent: String,
        revisionsByLine: [GitRevisionID]
    ) throws {
        guard revisionsByLine.count == sourceLineCount(sourceContent) else {
            throw GitBlameEvidenceError.lineCountMismatch
        }
        self.sourcePath = sourcePath
        self.headRevision = headRevision
        self.sourceDigest = try LifecycleDigest(
            value: LifecycleSHA256.hexDigest(Data(sourceContent.utf8))
        )
        self.revisionsByLine = revisionsByLine
    }

    func revision(forLine line: Int) -> GitRevisionID? {
        guard revisionsByLine.indices.contains(line - 1) else { return nil }
        return revisionsByLine[line - 1]
    }
}

struct GitBlameEvidence: Sendable {
    let headRevision: GitRevisionID
    private let factsBySource: [SourcePath: GitBlameSourceFacts]

    init(headRevision: GitRevisionID, sourceFacts: [GitBlameSourceFacts]) throws {
        var factsBySource: [SourcePath: GitBlameSourceFacts] = [:]
        for facts in sourceFacts {
            guard facts.headRevision == headRevision,
                factsBySource.updateValue(facts, forKey: facts.sourcePath) == nil
            else {
                throw GitBlameEvidenceError.inconsistentEvidence
            }
        }
        self.headRevision = headRevision
        self.factsBySource = factsBySource
    }

    func facts(for sourcePath: SourcePath) -> GitBlameSourceFacts? {
        factsBySource[sourcePath]
    }
}

enum GitBlameEvidenceAvailability: Sendable {
    case available(GitBlameEvidence)
    case unavailable(LifecycleReason)

    var capabilityState: SnapshotCapabilityState {
        switch self {
        case .available:
            .available
        case .unavailable(let reason):
            .unavailable(reason)
        }
    }

    var unavailableReason: LifecycleReason? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }
}

enum GitBlameEvidenceError: Error, Equatable {
    case inconsistentEvidence
    case lineCountMismatch
    case malformedOutput
}

func sourceLines(_ source: String) -> [String] {
    guard !source.isEmpty else { return [] }
    var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if source.hasSuffix("\n") { lines.removeLast() }
    return lines
}

private func sourceLineCount(_ source: String) -> Int {
    sourceLines(source).count
}
