import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax

public struct LifecycleIntroductionRequest: Sendable {
    public let artifactURL: URL
    public let repositoryURL: URL
    public let findingID: FindingID
    public let maximumRevisions: Int
    public let maximumFileBytes: Int

    public init(
        artifactURL: URL,
        repositoryURL: URL,
        findingID: FindingID,
        maximumRevisions: Int,
        maximumFileBytes: Int = 16 * 1_024 * 1_024
    ) {
        self.artifactURL = artifactURL.standardizedFileURL.resolvingSymlinksInPath()
        self.repositoryURL = repositoryURL.standardizedFileURL.resolvingSymlinksInPath()
        self.findingID = findingID
        self.maximumRevisions = maximumRevisions
        self.maximumFileBytes = maximumFileBytes
    }
}

public struct LifecycleIntroductionService: Sendable {
    let runner: any GitHistoryProcessRunning
    let timeoutSeconds: TimeInterval

    public init() {
        self.runner = GitHistorySubprocessRunner()
        self.timeoutSeconds = 10
    }

    init(runner: any GitHistoryProcessRunning, timeoutSeconds: TimeInterval = 10) {
        self.runner = runner
        self.timeoutSeconds = timeoutSeconds
    }

    public func infer(_ request: LifecycleIntroductionRequest) throws -> IntroductionRecording {
        guard request.maximumRevisions > 0, request.maximumFileBytes > 0 else {
            throw LifecycleAnalysisError.invalidHistoryBudget
        }
        let store = LifecycleArtifactStore(artifactURL: request.artifactURL)
        let artifact = try store.load()
        guard let finding = artifact.finding(id: request.findingID),
            let openingSnapshot = artifact.snapshot(id: finding.firstObservationSnapshotID)
        else {
            throw LifecycleContractError.missingFinding(request.findingID.rawValue)
        }

        let gitProvider = LifecycleGitSnapshotProvider(runner: runner, timeoutSeconds: timeoutSeconds)
        let gitSnapshot = try gitProvider.capture(
            root: request.repositoryURL,
            excludingGeneratedOutputs: [
                request.artifactURL,
                URL(fileURLWithPath: request.artifactURL.path + ".lock"),
            ]
        )
        guard
            case .available(
                let repositoryRoot,
                let headRevision,
                let workingTreeState,
                _,
                let statusDigest,
                _
            ) = gitSnapshot
        else {
            throw LifecycleAnalysisError.gitInspectionFailed("the requested path is not inside a Git repository")
        }
        let repositoryURL = URL(fileURLWithPath: repositoryRoot)
        let shallow = try isShallow(repositoryURL)
        let startingRevision = gitRevision(of: openingSnapshot)
        let limitingReasons = try ancestryReasons(
            startingRevision: startingRevision,
            headRevision: headRevision,
            repositoryURL: repositoryURL
        )
        let captured = try captureHistory(
            startingRevision: startingRevision,
            repositoryURL: repositoryURL,
            maximumRevisions: request.maximumRevisions,
            maximumFileBytes: request.maximumFileBytes
        )
        let gitAfterTraversal = try gitProvider.capture(
            root: request.repositoryURL,
            excludingGeneratedOutputs: [
                request.artifactURL,
                URL(fileURLWithPath: request.artifactURL.path + ".lock"),
            ]
        )
        guard gitAfterTraversal == gitSnapshot else {
            throw LifecycleAnalysisError.sourceChangedDuringCapture
        }
        let boundary = IntroductionHistoryBoundary(
            startingRevision: startingRevision,
            repositoryHeadRevision: headRevision,
            workingTreeState: workingTreeState,
            workingTreeStatusDigest: try LifecycleDigest(value: statusDigest),
            isShallow: shallow,
            maximumRevisions: request.maximumRevisions,
            frontierRevisions: captured.frontier,
            limitingReasons: limitingReasons
        )
        return try store.recordIntroduction(
            IntroductionHistoryEvidence(boundary: boundary, revisions: captured.revisions),
            for: request.findingID
        )
    }
}
