import Foundation
import SwiftDebtKit
import Testing

@Suite("Lifecycle introduction profile contract")
struct LifecycleIntroductionProfileTests {
    @Test("A canonical introduction profile round trips")
    func canonicalProfileDecodes() throws {
        let data = try Self.profileData()

        let profile = try JSONDecoder().decode(LifecycleIntroductionProfile.self, from: data)
        let encoded = try JSONEncoder().encode(profile)

        #expect(profile.reportKind == "swiftdebt-lifecycle-introduction-profile")
        #expect(profile.schemaVersion == 1)
        #expect(profile.evidenceRevisionCount == 2)
        #expect(profile.analyzedRevisionCount == 2)
        #expect(profile.reusedRevisionCount == 0)
        #expect(try JSONDecoder().decode(LifecycleIntroductionProfile.self, from: encoded) == profile)
    }

    @Test("Inconsistent profile identity and revision accounting fail closed")
    func invalidProfileIsRejected() throws {
        let corruptions: [(String, Any)] = [
            ("reportKind", "other-report"),
            ("schemaVersion", 2),
            ("maximumRevisions", 1),
            ("maximumFileBytes", 0),
            ("analyzedRevisionCount", -1),
            ("reusedRevisionCount", 1),
            ("operationElapsedNanoseconds", 0),
        ]
        for (key, value) in corruptions {
            var object = Self.profileObject
            object[key] = value
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(LifecycleIntroductionProfile.self, from: data)
            }
        }
        var overflow = Self.profileObject
        overflow["evidenceRevisionCount"] = 0
        overflow["analyzedRevisionCount"] = Int.max
        overflow["reusedRevisionCount"] = Int.max
        let overflowData = try JSONSerialization.data(
            withJSONObject: overflow,
            options: [.sortedKeys]
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(LifecycleIntroductionProfile.self, from: overflowData)
        }
    }

    private static func profileData() throws -> Data {
        try JSONSerialization.data(withJSONObject: profileObject, options: [.sortedKeys])
    }

    private static var profileObject: [String: Any] {
        [
            "reportKind": "swiftdebt-lifecycle-introduction-profile",
            "schemaVersion": 1,
            "findingID": "finding-profile-test",
            "maximumRevisions": 4,
            "maximumFileBytes": 16 * 1_024 * 1_024,
            "evidenceRevisionCount": 2,
            "analyzedRevisionCount": 2,
            "reusedRevisionCount": 0,
            "frontierRevisionCount": 0,
            "recordingStatus": "accepted",
            "operationElapsedNanoseconds": 1,
        ]
    }
}
