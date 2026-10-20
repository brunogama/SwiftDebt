import Dispatch
import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

enum PipelineProcessResult {
    case exited(Int32)
    case timedOut
    case unavailable(String)
}

struct PipelineProcessRunner: Sendable {
    func run(
        command: PipelineCommand,
        workingDirectory: URL,
        stdout: FileHandle,
        stderr: FileHandle
    ) -> PipelineProcessResult {
        #if os(macOS) || os(Linux)
            runSupported(
                command: command,
                workingDirectory: workingDirectory,
                stdout: stdout,
                stderr: stderr
            )
        #else
            .unavailable("Pipeline commands are unavailable on this platform")
        #endif
    }

    #if os(macOS) || os(Linux)
        private func runSupported(
            command: PipelineCommand,
            workingDirectory: URL,
            stdout: FileHandle,
            stderr: FileHandle
        ) -> PipelineProcessResult {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            process.currentDirectoryURL = workingDirectory
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr

            let termination = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in termination.signal() }
            do {
                try process.run()
            } catch {
                return .unavailable("command could not start: \(error)")
            }

            if termination.wait(timeout: .now() + command.timeoutSeconds) == .success {
                return .exited(process.terminationStatus)
            }

            if process.isRunning {
                process.terminate()
            }
            if termination.wait(timeout: .now() + 0.25) == .success {
                return .timedOut
            }

            if process.isRunning {
                forceKill(process.processIdentifier)
            }
            _ = termination.wait(timeout: .now() + 1)
            return .timedOut
        }

        /// Only the directly launched process is supervised. Configured commands must
        /// manage any descendants they create so those descendants do not outlive them.
        private func forceKill(_ processIdentifier: Int32) {
            #if canImport(Darwin)
                _ = Darwin.kill(processIdentifier, SIGKILL)
            #elseif canImport(Glibc)
                _ = Glibc.kill(processIdentifier, SIGKILL)
            #endif
        }
    #endif
}
