import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

final class RawTerminalMode {
    private var savedAttributes: termios?

    func enter() throws {
        guard savedAttributes == nil else {
            throw TerminalInteractionError.terminalMode("raw mode is already active")
        }

        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw TerminalInteractionError.posix(operation: "read terminal attributes", code: errno)
        }

        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            throw TerminalInteractionError.posix(operation: "enable raw terminal mode", code: errno)
        }
        savedAttributes = original
    }

    func restore() throws {
        guard var original = savedAttributes else { return }
        guard tcsetattr(STDIN_FILENO, TCSANOW, &original) == 0 else {
            throw TerminalInteractionError.posix(operation: "restore terminal attributes", code: errno)
        }
        savedAttributes = nil
    }

    deinit {
        guard var original = savedAttributes else { return }
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &original)
    }
}

enum POSIXTerminalInput {
    static func readByte() throws -> UInt8? {
        var byte: UInt8 = 0
        while true {
            let count = read(STDIN_FILENO, &byte, 1)
            if count == 1 { return byte }
            if count == 0 { return nil }
            if errno == EINTR { continue }
            throw TerminalInteractionError.posix(operation: "read terminal input", code: errno)
        }
    }

    static func readLine() throws -> String? {
        var bytes: [UInt8] = []
        while let byte = try readByte() {
            if byte == 10 || byte == 13 {
                return String(decoding: bytes, as: UTF8.self)
            }
            bytes.append(byte)
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }
}

enum TerminalInteractionError: Error, CustomStringConvertible {
    case clipboardUnavailable
    case editorNotConfigured
    case editorMissingFile
    case processFailed(name: String, status: Int32)
    case terminalMode(String)
    case posix(operation: String, code: Int32)

    var description: String {
        switch self {
        case .clipboardUnavailable:
            return "no supported clipboard command is available"
        case .editorNotConfigured:
            return "set VISUAL or EDITOR to enable editor jump"
        case .editorMissingFile:
            return "the selected debt item has no source file"
        case .processFailed(let name, let status):
            return "\(name) exited with status \(status)"
        case .terminalMode(let reason):
            return "terminal mode error: \(reason)"
        case .posix(let operation, let code):
            return "could not \(operation): \(String(cString: strerror(code)))"
        }
    }
}
