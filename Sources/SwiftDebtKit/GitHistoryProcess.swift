import Foundation

protocol GitHistoryProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) -> GitHistoryProcessResult
}

struct GitHistoryProcessResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

private struct GitProcessInput {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval
}

struct GitHistorySubprocessRunner: GitHistoryProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) -> GitHistoryProcessResult {
        #if os(macOS) || os(Linux)
            return runSupported(
                GitProcessInput(
                    executableURL: executableURL, arguments: arguments,
                    workingDirectory: workingDirectory, timeoutSeconds: timeoutSeconds))
        #else
            return GitHistoryProcessResult(
                exitCode: -1,
                stdout: "",
                stderr: "Git subprocesses are unavailable on this platform",
                timedOut: false
            )
        #endif
    }

    private func runSupported(_ input: GitProcessInput) -> GitHistoryProcessResult {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-debt-git-history-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            return try execute(input, temporary: temporary)
        } catch {
            return GitHistoryProcessResult(
                exitCode: -1, stdout: "", stderr: String(describing: error), timedOut: false)
        }
    }

    private func execute(_ input: GitProcessInput, temporary: URL) throws
        -> GitHistoryProcessResult
    {
        let stdoutURL = temporary.appendingPathComponent("stdout")
        let stderrURL = temporary.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }
        let process = Process()
        process.executableURL = input.executableURL
        process.arguments = input.arguments
        process.currentDirectoryURL = input.workingDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        let termination = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in termination.signal() }
        try process.run()
        let timedOut = termination.wait(timeout: .now() + input.timeoutSeconds) == .timedOut
        if timedOut { process.terminate() }
        process.waitUntilExit()
        return GitHistoryProcessResult(
            exitCode: process.terminationStatus, stdout: read(stdoutURL),
            stderr: read(stderrURL), timedOut: timedOut)
    }

    private func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

func diagnosticText(_ result: GitHistoryProcessResult) -> String {
    let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    if result.timedOut { return "process timed out" }
    if !stderr.isEmpty { return stderr }
    if !stdout.isEmpty { return stdout }
    return "exit status \(result.exitCode)"
}
