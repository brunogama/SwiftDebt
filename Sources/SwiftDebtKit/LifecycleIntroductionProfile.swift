import SwiftDebtLifecycle

/// Operational measurements for one bounded Git introduction query.
///
/// This sidecar is not lifecycle evidence and does not change the lifecycle
/// artifact. A reused revision is historical evidence consumed without
/// reanalyzing that revision during the current query.
public struct LifecycleIntroductionProfile: Codable, Equatable, Sendable {
    public let reportKind: String
    public let schemaVersion: Int
    public let findingID: FindingID
    public let maximumRevisions: Int
    public let maximumFileBytes: Int
    public let evidenceRevisionCount: Int
    public let analyzedRevisionCount: Int
    public let reusedRevisionCount: Int
    public let frontierRevisionCount: Int
    public let recordingStatus: IntroductionRecordingStatus
    public let operationElapsedNanoseconds: UInt64

    package init(
        findingID: FindingID,
        maximumRevisions: Int,
        maximumFileBytes: Int,
        evidenceRevisionCount: Int,
        analyzedRevisionCount: Int,
        reusedRevisionCount: Int,
        frontierRevisionCount: Int,
        recordingStatus: IntroductionRecordingStatus,
        operationElapsedNanoseconds: UInt64
    ) {
        self.reportKind = "swiftdebt-lifecycle-introduction-profile"
        self.schemaVersion = 1
        self.findingID = findingID
        self.maximumRevisions = maximumRevisions
        self.maximumFileBytes = maximumFileBytes
        self.evidenceRevisionCount = evidenceRevisionCount
        self.analyzedRevisionCount = analyzedRevisionCount
        self.reusedRevisionCount = reusedRevisionCount
        self.frontierRevisionCount = frontierRevisionCount
        self.recordingStatus = recordingStatus
        self.operationElapsedNanoseconds = operationElapsedNanoseconds
    }

    private enum CodingKeys: String, CodingKey {
        case reportKind
        case schemaVersion
        case findingID
        case maximumRevisions
        case maximumFileBytes
        case evidenceRevisionCount
        case analyzedRevisionCount
        case reusedRevisionCount
        case frontierRevisionCount
        case recordingStatus
        case operationElapsedNanoseconds
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let reportKind = try values.decode(String.self, forKey: .reportKind)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        let findingID = try values.decode(FindingID.self, forKey: .findingID)
        let maximumRevisions = try values.decode(Int.self, forKey: .maximumRevisions)
        let maximumFileBytes = try values.decode(Int.self, forKey: .maximumFileBytes)
        let evidenceRevisionCount = try values.decode(Int.self, forKey: .evidenceRevisionCount)
        let analyzedRevisionCount = try values.decode(Int.self, forKey: .analyzedRevisionCount)
        let reusedRevisionCount = try values.decode(Int.self, forKey: .reusedRevisionCount)
        let frontierRevisionCount = try values.decode(Int.self, forKey: .frontierRevisionCount)
        let recordingStatus = try values.decode(
            IntroductionRecordingStatus.self,
            forKey: .recordingStatus
        )
        let operationElapsedNanoseconds = try values.decode(
            UInt64.self,
            forKey: .operationElapsedNanoseconds
        )
        let (accountedRevisionCount, revisionCountOverflow) =
            analyzedRevisionCount.addingReportingOverflow(reusedRevisionCount)
        guard reportKind == "swiftdebt-lifecycle-introduction-profile",
            schemaVersion == 1,
            maximumRevisions > 0,
            maximumFileBytes > 0,
            evidenceRevisionCount >= 0,
            analyzedRevisionCount >= 0,
            reusedRevisionCount >= 0,
            frontierRevisionCount >= 0,
            operationElapsedNanoseconds > 0,
            !revisionCountOverflow,
            evidenceRevisionCount == accountedRevisionCount,
            evidenceRevisionCount <= maximumRevisions
        else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Introduction profile has inconsistent identity, budgets, or measurements."
                )
            )
        }
        self.init(
            findingID: findingID,
            maximumRevisions: maximumRevisions,
            maximumFileBytes: maximumFileBytes,
            evidenceRevisionCount: evidenceRevisionCount,
            analyzedRevisionCount: analyzedRevisionCount,
            reusedRevisionCount: reusedRevisionCount,
            frontierRevisionCount: frontierRevisionCount,
            recordingStatus: recordingStatus,
            operationElapsedNanoseconds: operationElapsedNanoseconds
        )
    }
}

package struct LifecycleIntroductionExecution: Sendable {
    package let recording: IntroductionRecording
    package let profile: LifecycleIntroductionProfile
}
