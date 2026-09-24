import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtInteractive

@Suite("Terminal debt explorer driver")
struct TerminalDebtExplorerDriverTests {
    @Test("Dispatches interactive commands until quit")
    func dispatchesInteractiveCommandsUntilQuit() throws {
        let harness = TerminalDriverHarness(
            keys: Array("jceppj/q".utf8),
            lines: ["worker 2"]
        )

        let result = try TerminalDebtExplorer.run(
            terminalDriverAnalysis(count: 4),
            environment: .interactiveTest,
            fallbackOutput: "fallback\n",
            dependencies: harness.dependencies(editor: "vim")
        )

        let finalState = try #require(result.finalState)
        #expect(!result.usedFallback)
        #expect(finalState.priorityFilter == .high)
        #expect(finalState.searchQuery == "worker 2")
        #expect(finalState.selectedItemID == "callable:Worker2.run")
        #expect(harness.copied.count == 1)
        #expect(harness.copied[0].contains("Worker 1 run"))
        #expect(
            harness.openedLocations == [
                DebtLocation(module: "Workspace", file: "Sources/Worker1.swift", line: 11, column: 3)
            ])
        #expect(harness.rawModeTransitions == Array(repeating: ["enter", "restore"], count: 8).flatMap { $0 })

        let transcript = harness.writes.joined()
        #expect(transcript.contains("Status: Copied source/context."))
        #expect(transcript.contains("Status: Opened Sources/Worker1.swift:11:3."))
        #expect(transcript.contains("Priority filter: high | Search: worker 2"))
        #expect(transcript.contains("> [high 80.0] Worker 2 run - Sources/Worker2.swift:12"))
    }

    @Test("Restores terminal mode when reading a command fails")
    func restoresTerminalModeWhenReadingCommandFails() {
        let harness = TerminalDriverHarness(keys: [], lines: [])
        harness.readError = TerminalDriverTestError.inputFailed

        #expect(throws: TerminalDriverTestError.inputFailed) {
            try TerminalDebtExplorer.run(
                terminalDriverAnalysis(count: 1),
                environment: .interactiveTest,
                fallbackOutput: "fallback\n",
                dependencies: harness.dependencies(editor: nil)
            )
        }
        #expect(harness.rawModeTransitions == ["enter", "restore"])
    }

    @Test("Restores terminal mode before keyboard exit", arguments: [UInt8(3), UInt8(4), UInt8(113)])
    func restoresTerminalModeBeforeKeyboardExit(key: UInt8) throws {
        let harness = TerminalDriverHarness(keys: [key], lines: [])

        let result = try TerminalDebtExplorer.run(
            terminalDriverAnalysis(count: 1),
            environment: .interactiveTest,
            fallbackOutput: "fallback\n",
            dependencies: harness.dependencies(editor: nil)
        )

        #expect(!result.usedFallback)
        #expect(harness.rawModeTransitions == ["enter", "restore"])
    }

    @Test("Keeps the moved selection inside the rendered viewport")
    func keepsMovedSelectionInsideRenderedViewport() throws {
        let harness = TerminalDriverHarness(
            keys: Array(repeating: UInt8(106), count: 21) + [UInt8(113)],
            lines: []
        )

        try TerminalDebtExplorer.run(
            terminalDriverAnalysis(count: 30),
            environment: .interactiveTest,
            fallbackOutput: "fallback\n",
            dependencies: harness.dependencies(editor: nil)
        )

        let screen = try #require(harness.writes.last)
        #expect(screen.contains("  ... 2 earlier items"))
        #expect(screen.contains("> [medium 55.0] Worker 21 run - Sources/Worker21.swift:31"))
    }

    @Test("Keeps editor executable and source location as process arguments")
    func keepsEditorAndLocationAsProcessArguments() throws {
        let location = DebtLocation(
            module: "Workspace",
            file: "Sources/Worker.swift;touch-owned",
            line: 42,
            column: 7
        )
        let launch = try TerminalEditorLaunch(
            editor: "vim;echo-owned",
            location: location
        )

        #expect(launch.executableURL.path == "/usr/bin/env")
        #expect(
            launch.arguments == [
                "vim;echo-owned",
                "+42",
                "Sources/Worker.swift;touch-owned",
            ])

        let codeLaunch = try TerminalEditorLaunch(
            editor: "code --wait",
            location: location,
            sourceRoot: URL(fileURLWithPath: "/workspace")
        )
        #expect(codeLaunch.executableURL.path == "/usr/bin/env")
        #expect(
            codeLaunch.arguments == [
                "code",
                "--wait",
                "--goto",
                "/workspace/Sources/Worker.swift;touch-owned:42:7",
            ])
    }
}
