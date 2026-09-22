import Foundation
import SCMACore

/// The outcome of an interactive run or its non-interactive fallback.
public struct TerminalDebtExplorerRunResult: Equatable, Sendable {
    public let usedFallback: Bool
    public let reason: String?
    public let finalState: DebtExplorerState?

    public init(usedFallback: Bool, reason: String?, finalState: DebtExplorerState?) {
        self.usedFallback = usedFallback
        self.reason = reason
        self.finalState = finalState
    }
}

extension TerminalDebtExplorer {
    /// Runs the debt explorer until input closes or the user quits.
    @discardableResult
    public static func run(
        _ analysis: RankedDebtAnalysis,
        environment: TerminalEnvironment = .current(),
        fallbackOutput: String,
        dependencies: TerminalDebtExplorerDependencies = .live()
    ) throws -> TerminalDebtExplorerRunResult {
        let capability = TerminalCapability.detect(environment)
        guard capability.supportsInteractive else {
            try dependencies.write(fallbackOutput)
            return TerminalDebtExplorerRunResult(
                usedFallback: true,
                reason: capability.reason,
                finalState: nil
            )
        }

        var state = DebtExplorerState(analysis: analysis)
        var status: String?
        try redraw(state: state, analysis: analysis, status: status, dependencies: dependencies)

        commandLoop: while true {
            guard let key = try readKey(dependencies: dependencies) else { break }
            switch TerminalDebtExplorerCommand(key: key) {
            case .moveDown:
                state = DebtExplorerReducer.reduce(state, .moveSelection(1))
                status = nil
            case .moveUp:
                state = DebtExplorerReducer.reduce(state, .moveSelection(-1))
                status = nil
            case .cyclePriority:
                state = DebtExplorerReducer.reduce(state, .cyclePriorityFilter)
                status = nil
            case .search:
                try dependencies.write("Search query (empty clears): ")
                guard let query = try dependencies.readLine() else { break commandLoop }
                state = DebtExplorerReducer.reduce(state, .setSearchQuery(query))
                status = query.isEmpty ? "Search cleared." : "Search updated."
            case .copyContext:
                status = copySelectedContext(state: state, dependencies: dependencies)
            case .openEditor:
                status = openSelectedSource(state: state, dependencies: dependencies)
            case .quit:
                break commandLoop
            case .unknown(let key):
                status = "Unknown command: \(String(decoding: [key], as: UTF8.self))"
            }
            try redraw(state: state, analysis: analysis, status: status, dependencies: dependencies)
        }

        return TerminalDebtExplorerRunResult(usedFallback: false, reason: nil, finalState: state)
    }

    private static func readKey(dependencies: TerminalDebtExplorerDependencies) throws -> UInt8? {
        try dependencies.enterRawMode()
        let result: Result<UInt8?, any Error>
        do {
            result = .success(try dependencies.readKey())
        } catch {
            result = .failure(error)
        }
        try dependencies.restoreTerminalMode()
        return try result.get()
    }

    private static func redraw(
        state: DebtExplorerState,
        analysis: RankedDebtAnalysis,
        status: String?,
        dependencies: TerminalDebtExplorerDependencies
    ) throws {
        let screen = renderInteractiveScreen(
            state: state,
            analysis: analysis,
            editor: dependencies.editor,
            status: status
        )
        try dependencies.write("\u{001B}[2J\u{001B}[H" + screen)
    }

    private static func copySelectedContext(
        state: DebtExplorerState,
        dependencies: TerminalDebtExplorerDependencies
    ) -> String {
        guard let detail = state.selectedDetail(editor: dependencies.editor) else {
            return "Nothing to copy."
        }
        do {
            try dependencies.copy(detail.sourceContext)
            return "Copied source/context."
        } catch {
            return "Copy failed: \(error)"
        }
    }

    private static func openSelectedSource(
        state: DebtExplorerState,
        dependencies: TerminalDebtExplorerDependencies
    ) -> String {
        guard let selectedItem = state.selectedItem else { return "Nothing to open." }
        do {
            try dependencies.openEditor(selectedItem.item.entity.location)
            return "Opened \(selectedItem.item.entity.location.debtExplorerLocation)."
        } catch {
            return "Editor jump failed: \(error)"
        }
    }
}

private enum TerminalDebtExplorerCommand {
    case moveDown
    case moveUp
    case cyclePriority
    case search
    case copyContext
    case openEditor
    case quit
    case unknown(UInt8)

    init(key: UInt8) {
        switch key {
        case 106: self = .moveDown
        case 107: self = .moveUp
        case 112: self = .cyclePriority
        case 47: self = .search
        case 99: self = .copyContext
        case 101: self = .openEditor
        case 3, 4, 113: self = .quit
        default: self = .unknown(key)
        }
    }
}
