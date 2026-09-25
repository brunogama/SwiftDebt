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
    private static let repositoryOverrideKeys: Set<String> = [
        "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_CEILING_DIRECTORIES", "GIT_DISCOVERY_ACROSS_FILESYSTEM",
        "GIT_NAMESPACE", "GIT_PREFIX", "GIT_SUPER_PREFIX",
    ]

    static func repositoryScopedEnvironment(_ inherited: [String: String]) -> [String: String] {
        inherited.filter { !repositoryOverrideKeys.contains($0.key) }
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) -> GitHistoryProcessResult {
        #if os(macOS) || os(Linux)
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift-debt-git-history-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temporary) }
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
                process.executableURL = executableURL
                process.arguments = arguments
                process.currentDirectoryURL = workingDirectory
                process.environment = Self.repositoryScopedEnvironment(ProcessInfo.processInfo.environment)
                process.standardOutput = stdout
                process.standardError = stderr
                let termination = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in termination.signal() }
                try process.run()
                if termination.wait(timeout: .now() + timeoutSeconds) == .timedOut {
                    process.terminate()
                    process.waitUntilExit()
                    return GitHistoryProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: read(stdoutURL),
                        stderr: read(stderrURL),
                        timedOut: true
                    )
                }
                process.waitUntilExit()
                return GitHistoryProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: read(stdoutURL),
                    stderr: read(stderrURL),
                    timedOut: false
                )
            } catch {
                return GitHistoryProcessResult(
                    exitCode: -1, stdout: "", stderr: String(describing: error), timedOut: false)
            }
        #else
            return GitHistoryProcessResult(
                exitCode: -1,
                stdout: "",
                stderr: "Git subprocesses are unavailable on this platform",
                timedOut: false
            )
        #endif
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
