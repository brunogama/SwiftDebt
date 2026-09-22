import Foundation
import SwiftDebtCore

/// Side-effect boundaries used by the interactive terminal driver.
public struct TerminalDebtExplorerDependencies {
    public let readKey: () throws -> UInt8?
    public let readLine: () throws -> String?
    public let write: (String) throws -> Void
    public let copy: (String) throws -> Void
    public let openEditor: (DebtLocation) throws -> Void
    public let enterRawMode: () throws -> Void
    public let restoreTerminalMode: () throws -> Void
    public let editor: String?

    public init(
        readKey: @escaping () throws -> UInt8?,
        readLine: @escaping () throws -> String?,
        write: @escaping (String) throws -> Void,
        copy: @escaping (String) throws -> Void,
        openEditor: @escaping (DebtLocation) throws -> Void,
        enterRawMode: @escaping () throws -> Void,
        restoreTerminalMode: @escaping () throws -> Void,
        editor: String?
    ) {
        self.readKey = readKey
        self.readLine = readLine
        self.write = write
        self.copy = copy
        self.openEditor = openEditor
        self.enterRawMode = enterRawMode
        self.restoreTerminalMode = restoreTerminalMode
        self.editor = editor
    }

    /// Creates the POSIX terminal, clipboard, and editor integrations used by the CLI.
    public static func live(
        editor: String? = ProcessInfo.processInfo.environment["VISUAL"]
            ?? ProcessInfo.processInfo.environment["EDITOR"],
        sourceRoot: URL? = nil
    ) -> TerminalDebtExplorerDependencies {
        let terminalMode = RawTerminalMode()
        return TerminalDebtExplorerDependencies(
            readKey: POSIXTerminalInput.readByte,
            readLine: POSIXTerminalInput.readLine,
            write: { text in
                try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
            },
            copy: TerminalClipboard.copy,
            openEditor: { location in
                guard let editor else { throw TerminalInteractionError.editorNotConfigured }
                try TerminalEditorLaunch(editor: editor, location: location, sourceRoot: sourceRoot).run()
            },
            enterRawMode: terminalMode.enter,
            restoreTerminalMode: terminalMode.restore,
            editor: editor
        )
    }
}
