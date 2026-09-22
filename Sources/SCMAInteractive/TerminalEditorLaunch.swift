import Foundation
import SCMACore

struct TerminalEditorLaunch: Equatable {
    let executableURL: URL
    let arguments: [String]

    init(editor: String, location: DebtLocation, sourceRoot: URL? = nil) throws {
        let editor = editor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !editor.isEmpty else { throw TerminalInteractionError.editorNotConfigured }
        guard let file = location.file else { throw TerminalInteractionError.editorMissingFile }

        let editorArguments = Self.editorArguments(editor)
        guard let executable = editorArguments.first else {
            throw TerminalInteractionError.editorNotConfigured
        }
        let fileArgument = Self.fileArgument(file, sourceRoot: sourceRoot)
        let sourceArguments = Self.sourceArguments(
            editor: executable,
            file: fileArgument,
            line: location.line ?? 1,
            column: location.column ?? 1
        )
        if executable.contains("/") {
            executableURL = URL(fileURLWithPath: executable)
            arguments = Array(editorArguments.dropFirst()) + sourceArguments
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = editorArguments + sourceArguments
        }
    }

    func run() throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TerminalInteractionError.processFailed(
                name: executableURL.lastPathComponent,
                status: process.terminationStatus
            )
        }
    }

    private static func editorArguments(_ editor: String) -> [String] {
        if FileManager.default.isExecutableFile(atPath: editor) {
            return [editor]
        }
        return editor.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func fileArgument(_ file: String, sourceRoot: URL?) -> String {
        guard !(file as NSString).isAbsolutePath, let sourceRoot else { return file }
        return sourceRoot.appendingPathComponent(file).standardizedFileURL.path
    }

    private static func sourceArguments(editor: String, file: String, line: Int, column: Int) -> [String] {
        switch URL(fileURLWithPath: editor).lastPathComponent {
        case "code", "code-insiders", "codium", "cursor":
            return ["--goto", "\(file):\(line):\(column)"]
        default:
            return ["+\(line)", file]
        }
    }
}

enum TerminalClipboard {
    static func copy(_ text: String) throws {
        let command = try clipboardCommand()
        let process = Process()
        let input = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardInput = input

        try process.run()
        do {
            try input.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            try input.fileHandleForWriting.close()
        } catch {
            try? input.fileHandleForWriting.close()
            process.terminate()
            throw error
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TerminalInteractionError.processFailed(
                name: command.executableURL.lastPathComponent,
                status: process.terminationStatus
            )
        }
    }

    private static func clipboardCommand() throws -> (executableURL: URL, arguments: [String]) {
        let candidates: [(String, [String])] = [
            ("/usr/bin/pbcopy", []),
            ("/usr/bin/wl-copy", []),
            ("/usr/bin/xclip", ["-selection", "clipboard"]),
        ]
        guard let command = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.0) }) else {
            throw TerminalInteractionError.clipboardUnavailable
        }
        return (URL(fileURLWithPath: command.0), command.1)
    }
}
