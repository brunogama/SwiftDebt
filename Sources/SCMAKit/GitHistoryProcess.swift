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

struct GitHistorySubprocessRunner: GitHistoryProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) -> GitHistoryProcessResult {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("scma-git-history-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let stdoutURL = temporary.appendingPathComponent("stdout")
            let stderrURL = temporary.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stdout = try FileHandle(forWritingTo: stdoutURL)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer { try? stdout.close(); try? stderr.close() }

            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            while process.isRunning {
                let remainingTime = deadline.timeIntervalSinceNow
                if remainingTime <= 0 {
                    process.terminate()
                    process.waitUntilExit()
                    return GitHistoryProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: read(stdoutURL),
                        stderr: read(stderrURL),
                        timedOut: true
                    )
                }
                Thread.sleep(forTimeInterval: min(remainingTime, 0.1))
            }
            process.waitUntilExit()
            return GitHistoryProcessResult(
                exitCode: process.terminationStatus,
                stdout: read(stdoutURL),
                stderr: read(stderrURL),
                timedOut: false
            )
        } catch {
            return GitHistoryProcessResult(exitCode: -1, stdout: "", stderr: String(describing: error), timedOut: false)
        }
    }

    private func read(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
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
