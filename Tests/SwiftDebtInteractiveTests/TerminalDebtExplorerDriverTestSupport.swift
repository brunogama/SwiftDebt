import SwiftDebtCore
import SwiftDebtInteractive

final class TerminalDriverHarness {
    var keys: [UInt8]
    var lines: [String]
    var writes: [String] = []
    var copied: [String] = []
    var openedLocations: [DebtLocation] = []
    var rawModeTransitions: [String] = []
    var readError: (any Error)?

    init(keys: [UInt8], lines: [String]) {
        self.keys = keys
        self.lines = lines
    }

    func dependencies(editor: String?) -> TerminalDebtExplorerDependencies {
        TerminalDebtExplorerDependencies(
            readKey: {
                if let readError = self.readError { throw readError }
                return self.keys.isEmpty ? nil : self.keys.removeFirst()
            },
            readLine: {
                self.lines.isEmpty ? nil : self.lines.removeFirst()
            },
            write: { self.writes.append($0) },
            copy: { self.copied.append($0) },
            openEditor: { self.openedLocations.append($0) },
            enterRawMode: { self.rawModeTransitions.append("enter") },
            restoreTerminalMode: { self.rawModeTransitions.append("restore") },
            editor: editor
        )
    }
}

enum TerminalDriverTestError: Error {
    case inputFailed
}

extension TerminalEnvironment {
    static let interactiveTest = TerminalEnvironment(
        standardInputIsTTY: true,
        standardOutputIsTTY: true,
        term: "xterm-256color",
        ci: nil
    )
}

func terminalDriverAnalysis(count: Int) -> RankedDebtAnalysis {
    let items = (0..<count).map { index in
        terminalDriverItem(
            id: "callable:Worker\(index).run",
            name: "Worker \(index) run",
            priority: index.isMultiple(of: 2) ? .high : .medium,
            score: index.isMultiple(of: 2) ? 80 : 55,
            file: "Sources/Worker\(index).swift",
            line: 10 + index
        )
    }
    return RankedDebtAnalysis(
        options: DebtAnalysisOptions(aggregationStrategy: .none),
        items: items,
        aggregations: [],
        compactItems: [],
        summary: DebtAnalysisSummary(
            totalItemCount: count,
            rankedItemCount: count,
            aggregationCount: 0,
            unavailableEvidenceCount: 0,
            priorityCounts: ["high": (count + 1) / 2, "medium": count / 2]
        )
    )
}

private func terminalDriverItem(
    id: String,
    name: String,
    priority: Priority,
    score: Double,
    file: String,
    line: Int
) -> RankedDebtItem {
    let location = DebtLocation(module: "Workspace", file: file, line: line, column: 3)
    let evidence = DebtEvidence(
        id: "\(id):complexity",
        kind: "swift.cognitive-complexity",
        weight: 1,
        normalizedScore: score,
        rawValue: "cognitive=\(Int(score / 5))",
        location: location,
        note: "measured"
    )
    return RankedDebtItem(
        item: DebtItem(
            id: id,
            entity: DebtEntity(id: id, displayName: name, level: .callable, location: location),
            evidence: [evidence]
        ),
        score: DebtScore(
            value: score,
            priority: priority,
            breakdown: DebtScoreBreakdown(
                totalConfiguredWeight: 1,
                totalAvailableWeight: 1,
                contributions: [],
                unavailableEvidence: []
            )
        ),
        category: "swift",
        explanation: "Complexity concentrates change risk.",
        recommendation: "Extract smaller operations."
    )
}
