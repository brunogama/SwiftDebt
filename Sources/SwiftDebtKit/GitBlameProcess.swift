import Foundation

struct GitBlameProcess: Sendable {
    private let runner: any GitHistoryProcessRunning
    private let timeoutSeconds: TimeInterval

    init(runner: any GitHistoryProcessRunning, timeoutSeconds: TimeInterval) {
        self.runner = runner
        self.timeoutSeconds = timeoutSeconds
    }

    func require(
        _ arguments: [String],
        operation: String,
        executable: URL,
        repository: URL
    ) throws -> String {
        let result = run(arguments, executable: executable, repository: repository)
        guard result.exitCode == 0, !result.timedOut else {
            throw ProviderFailure(
                code: "git-blame-provider-failed",
                message: "The Git blame provider could not \(operation): \(singleLine(diagnosticText(result)))."
            )
        }
        return result.stdout
    }

    func run(
        _ arguments: [String],
        executable: URL,
        repository: URL
    ) -> GitHistoryProcessResult {
        runner.run(
            executableURL: executable,
            arguments: arguments,
            workingDirectory: repository,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func singleLine(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

struct ProviderFailure: Error {
    let code: String
    let message: String
}
