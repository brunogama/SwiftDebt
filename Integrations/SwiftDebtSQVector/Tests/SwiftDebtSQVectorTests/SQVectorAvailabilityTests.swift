import SwiftDebtSQVector
import Testing

@Suite("SQVector adapter availability")
struct SQVectorAvailabilityTests {
    @Test("reports the static product state explicitly")
    func availability() async throws {
        #if canImport(SQVector)
            #expect(SQVectorExactCandidateIndex.availability == .available)
        #else
            #expect(
                SQVectorExactCandidateIndex.availability
                    == .unavailable(.unsupportedPlatform)
            )
            let index = try await SQVectorExactCandidateIndex.openInMemory(
                identity: makeIdentity()
            )
            let result = try await index.nearest(to: [1, 0], limit: 1)
            #expect(result == .unavailable(.unsupportedPlatform))
        #endif
    }
}
