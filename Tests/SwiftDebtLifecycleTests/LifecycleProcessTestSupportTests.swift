import Foundation
import Testing

@Suite("Lifecycle subprocess capture")
struct LifecycleProcessTestSupportTests {
    @Test("Output larger than a pipe buffer completes without blocking")
    func capturesLargeOutput() throws {
        let result = try runLifecycleProcess(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf '%0131072d' 0"],
            directory: FileManager.default.temporaryDirectory,
            timeout: 5
        )
        #expect(result.status == 0)
        #expect(result.standardOutput.utf8.count == 131_072)
        #expect(result.standardError.isEmpty)
    }

    @Test("A timed-out process is terminated before output capture is released")
    func terminatesTimedOutProcess() throws {
        do {
            _ = try runLifecycleProcess(
                executable: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["1"],
                directory: FileManager.default.temporaryDirectory,
                timeout: 0.01
            )
            Issue.record("Expected the subprocess deadline to expire")
        } catch LifecycleProcessFailure.timedOut {
            // The helper reaped the process before returning this error.
        }
    }

    @Test("A child ignoring SIGTERM is forcefully reaped")
    func forcefullyReapsChildIgnoringTermination() throws {
        do {
            _ = try runLifecycleProcess(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; while :; do :; done"],
                directory: FileManager.default.temporaryDirectory,
                timeout: 0.25
            )
            Issue.record("Expected the subprocess deadline to expire")
        } catch LifecycleProcessFailure.timedOut {
            // The helper sent SIGKILL and reaped the child before returning.
        }
    }
}
