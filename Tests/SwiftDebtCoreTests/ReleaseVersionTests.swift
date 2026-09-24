import Testing

@testable import SwiftDebtCore

@Suite("Release version")
struct ReleaseVersionTests {
    @Test("Runtime release version is canonical semantic version")
    func runtimeVersionIsCanonical() {
        let components = SwiftDebtRelease.version.split(separator: ".")

        #expect(components.count == 3)
        #expect(components.allSatisfy { Int($0) != nil })
        #expect(components.map(String.init).joined(separator: ".") == SwiftDebtRelease.version)
    }
}
