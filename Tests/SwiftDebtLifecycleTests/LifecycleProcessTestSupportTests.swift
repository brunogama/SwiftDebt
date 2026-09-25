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
}
