import Foundation
import SCMACore

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public struct TerminalEnvironment: Equatable, Sendable {
    public let standardInputIsTTY: Bool
    public let standardOutputIsTTY: Bool
    public let term: String?
    public let ci: String?

    public init(standardInputIsTTY: Bool, standardOutputIsTTY: Bool, term: String?, ci: String?) {
        self.standardInputIsTTY = standardInputIsTTY
        self.standardOutputIsTTY = standardOutputIsTTY
        self.term = term
        self.ci = ci
    }

    public static func current(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> TerminalEnvironment {
        TerminalEnvironment(
            standardInputIsTTY: isTTY(STDIN_FILENO),
            standardOutputIsTTY: isTTY(STDOUT_FILENO),
            term: environment["TERM"],
            ci: environment["CI"]
        )
    }
}

public struct TerminalCapability: Equatable, Sendable {
    public let supportsInteractive: Bool
    public let reason: String?

    public static func detect(_ environment: TerminalEnvironment) -> TerminalCapability {
        if !environment.standardInputIsTTY {
            return TerminalCapability(supportsInteractive: false, reason: "stdin is not a TTY")
        }
        if !environment.standardOutputIsTTY {
            return TerminalCapability(supportsInteractive: false, reason: "stdout is not a TTY")
        }
        if let ci = environment.ci, !ci.isEmpty, ci.lowercased() != "false" {
            return TerminalCapability(supportsInteractive: false, reason: "CI terminal")
        }
        guard let term = environment.term, !term.isEmpty else {
            return TerminalCapability(supportsInteractive: false, reason: "TERM missing")
        }
        if term.lowercased() == "dumb" {
            return TerminalCapability(supportsInteractive: false, reason: "TERM=dumb")
        }
        return TerminalCapability(supportsInteractive: true, reason: nil)
    }
}

public struct TerminalDebtExplorerOutput: Equatable, Sendable {
    public let text: String
    public let usedFallback: Bool
    public let reason: String?

    public init(text: String, usedFallback: Bool, reason: String?) {
        self.text = text
        self.usedFallback = usedFallback
        self.reason = reason
    }
}

public enum TerminalDebtExplorer {
    public static func render(
        _ analysis: RankedDebtAnalysis,
        environment: TerminalEnvironment = .current(),
        fallbackOutput: String,
        editor: String? = ProcessInfo.processInfo.environment["VISUAL"] ?? ProcessInfo.processInfo.environment["EDITOR"]
    ) -> TerminalDebtExplorerOutput {
        let capability = TerminalCapability.detect(environment)
        guard capability.supportsInteractive else {
            return TerminalDebtExplorerOutput(text: fallbackOutput, usedFallback: true, reason: capability.reason)
        }
        let state = DebtExplorerState(analysis: analysis)
        return TerminalDebtExplorerOutput(
            text: renderInteractiveScreen(state: state, analysis: analysis, editor: editor),
            usedFallback: false,
            reason: nil
        )
    }

    public static func renderInteractiveScreen(
        state: DebtExplorerState,
        analysis: RankedDebtAnalysis,
        editor: String? = nil,
        listLimit: Int = 20
    ) -> String {
        var lines: [String] = [
            "SwiftSCMA debt explorer",
            "Ranked items: \(analysis.summary.rankedItemCount) | Visible: \(state.visibleItemIDs.count)",
            "Priority filter: \(state.priorityFilter?.rawValue ?? "all") | Search: \(state.searchQuery.isEmpty ? "none" : state.searchQuery)",
            "Commands: j/k move | p priority | / search | c copy source/context | e editor jump | q quit",
            "",
            "Ranked debt",
        ]
        let visible = visibleItems(for: state, limit: listLimit)
        if visible.isEmpty {
            lines.append("  No debt items match the current filters.")
        } else {
            for (offset, item) in visible.enumerated() {
                let absoluteIndex = offset
                let marker = state.visibleItemIDs.indices.contains(absoluteIndex)
                    && state.visibleItemIDs[absoluteIndex] == state.selectedItemID ? ">" : " "
                lines.append("\(marker) \(listLine(for: item))")
            }
            if state.visibleItemIDs.count > visible.count {
                lines.append("  ... \(state.visibleItemIDs.count - visible.count) more items")
            }
        }
        if let detail = state.selectedDetail(editor: editor) {
            lines += [
                "",
                "Detail",
                "Title: \(detail.title)",
                "Location: \(detail.location)",
                "Priority: \(detail.priority)",
                "Score: \(detail.score)",
                "Why: \(detail.explanation)",
                "Action: \(detail.recommendation)",
                "",
                "Copyable source/context",
                detail.sourceContext,
            ]
            if let editorCommand = detail.editorCommand {
                lines += ["", "Editor jump", editorCommand]
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func visibleItems(for state: DebtExplorerState, limit: Int) -> [RankedDebtItem] {
        guard limit > 0 else { return [] }
        var matches: [RankedDebtItem] = []
        matches.reserveCapacity(min(limit, state.visibleItemIDs.count))
        var remainingIDs = Set(state.visibleItemIDs.prefix(limit))
        for item in state.items where remainingIDs.contains(item.item.id) {
            matches.append(item)
            remainingIDs.remove(item.item.id)
            if matches.count == limit { break }
        }
        return matches.sorted { lhs, rhs in
            guard let lhsIndex = state.visibleItemIDs.firstIndex(of: lhs.item.id),
                let rhsIndex = state.visibleItemIDs.firstIndex(of: rhs.item.id)
            else { return lhs.item.id < rhs.item.id }
            return lhsIndex < rhsIndex
        }
    }

    private static func listLine(for item: RankedDebtItem) -> String {
        let priority = item.score.priority?.rawValue ?? "unscored"
        let score = item.score.value.map { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "N/A"
        let file = item.item.entity.location.file ?? "unknown"
        let line = item.item.entity.location.line.map(String.init) ?? "?"
        return "[\(priority) \(score)] \(item.item.entity.displayName) - \(file):\(line)"
    }
}

private func isTTY(_ fileDescriptor: Int32) -> Bool {
    #if canImport(Darwin) || canImport(Glibc)
        return isatty(fileDescriptor) == 1
    #else
        return false
    #endif
}
