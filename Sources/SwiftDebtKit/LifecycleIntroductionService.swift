import Dispatch
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
    package let profileOutputURL: URL?

    public init(
        artifactURL: URL,
        repositoryURL: URL,
        findingID: FindingID,
        maximumRevisions: Int,
        maximumFileBytes: Int = 16 * 1_024 * 1_024
    ) {
        self.init(
            artifactURL: artifactURL,
            repositoryURL: repositoryURL,
            findingID: findingID,
            maximumRevisions: maximumRevisions,
            maximumFileBytes: maximumFileBytes,
            profileOutputURL: nil
        )
    }

    package init(
        artifactURL: URL,
        repositoryURL: URL,
        findingID: FindingID,
        maximumRevisions: Int,
        maximumFileBytes: Int,
        profileOutputURL: URL?
    ) {
        self.artifactURL = LifecycleIntroductionOutputPath.canonical(artifactURL)
        self.repositoryURL = LifecycleIntroductionOutputPath.canonical(repositoryURL)
        self.findingID = findingID
        self.maximumRevisions = maximumRevisions
        self.maximumFileBytes = maximumFileBytes
        self.profileOutputURL = profileOutputURL.map {
            LifecycleIntroductionOutputPath.canonical($0)
        }
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
        try perform(request).recording
    }

    package func inferProfiled(
        _ request: LifecycleIntroductionRequest
    ) throws -> LifecycleIntroductionExecution {
        guard let profileOutputURL = request.profileOutputURL else {
            throw WorkspaceError("Introduction profile output is required for profiled inference")
        }
        let started = DispatchTime.now().uptimeNanoseconds
        let result = try perform(request)
        let elapsed = max(DispatchTime.now().uptimeNanoseconds - started, 1)
        let evidence = result.recording.conclusion.evidence
        let execution = LifecycleIntroductionExecution(
            recording: result.recording,
            profile: LifecycleIntroductionProfile(
                findingID: request.findingID,
                maximumRevisions: request.maximumRevisions,
                maximumFileBytes: request.maximumFileBytes,
                evidenceRevisionCount: evidence.revisions.count,
                analyzedRevisionCount: result.analyzedRevisionCount,
                reusedRevisionCount: result.reusedRevisionCount,
                frontierRevisionCount: evidence.boundary.frontierRevisions.count,
                recordingStatus: result.recording.status,
                operationElapsedNanoseconds: elapsed
            )
        )
        try LifecycleIntroductionProfileOutput.write(
            execution.profile,
            to: profileOutputURL,
            artifactURL: request.artifactURL,
            repositoryURL: result.repositoryURL
        )
        return execution
    }

    private func perform(_ request: LifecycleIntroductionRequest) throws -> (
        recording: IntroductionRecording,
        analyzedRevisionCount: Int,
        reusedRevisionCount: Int,
        repositoryURL: URL
    ) {
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

        let excludedOutputs =
            [
                request.artifactURL,
                URL(fileURLWithPath: request.artifactURL.path + ".lock"),
            ] + (request.profileOutputURL.map { [$0] } ?? [])
        let gitProvider = LifecycleGitSnapshotProvider(runner: runner, timeoutSeconds: timeoutSeconds)
        let gitSnapshot = try gitProvider.capture(
            root: request.repositoryURL,
            excludingGeneratedOutputs: excludedOutputs
        )
        guard
            case .available(
                let repositoryRoot,
                let headRevision,
                let workingTreeState,
                _,
                let statusDigest,
                _,
                _
            ) = gitSnapshot
        else {
            throw LifecycleAnalysisError.gitInspectionFailed("the requested path is not inside a Git repository")
        }
        let repositoryURL = URL(fileURLWithPath: repositoryRoot)
        if let profileOutputURL = request.profileOutputURL,
            LifecycleIntroductionOutputPath.contains(profileOutputURL, within: repositoryURL)
        {
            throw WorkspaceError("Introduction profile output must be outside the analyzed repository")
        }
        if let profileOutputURL = request.profileOutputURL {
            try LifecycleIntroductionProfileOutput.prepare(
                profileOutputURL,
                artifactURL: request.artifactURL,
                repositoryURL: repositoryURL
            )
        }
        let shallow = try isShallow(repositoryURL)
        let startingRevision = gitRevision(of: openingSnapshot)
        let limitingReasons = try ancestryReasons(
            startingRevision: startingRevision,
            headRevision: headRevision,
            repositoryURL: repositoryURL
        )
        let status = try LifecycleDigest(value: statusDigest)
        let reuse = LifecycleIntroductionHistoryReuse(
            artifact: artifact,
            findingID: request.findingID,
            query: LifecycleIntroductionReuseQuery(
                startingRevision: startingRevision,
                repositoryHeadRevision: headRevision,
                workingTreeState: workingTreeState,
                workingTreeStatusDigest: status,
                isShallow: shallow,
                maximumRevisions: request.maximumRevisions,
                limitingReasons: limitingReasons
            )
        )
        let captured = try captureHistory(
            startingRevision: startingRevision,
            repositoryURL: repositoryURL,
            maximumRevisions: request.maximumRevisions,
            maximumFileBytes: request.maximumFileBytes,
            reuse: reuse
        )
        let gitAfterTraversal = try gitProvider.capture(
            root: request.repositoryURL,
            excludingGeneratedOutputs: excludedOutputs
        )
        guard gitAfterTraversal == gitSnapshot else {
            throw LifecycleAnalysisError.sourceChangedDuringCapture
        }
        let boundary = IntroductionHistoryBoundary(
            startingRevision: startingRevision,
            repositoryHeadRevision: headRevision,
            workingTreeState: workingTreeState,
            workingTreeStatusDigest: status,
            isShallow: shallow,
            maximumRevisions: request.maximumRevisions,
            frontierRevisions: captured.frontier,
            limitingReasons: limitingReasons
        )
        let recording = try store.recordIntroduction(
            IntroductionHistoryEvidence(boundary: boundary, revisions: captured.revisions),
            for: request.findingID
        )
        return (
            recording,
            captured.analyzedRevisionCount,
            captured.reusedRevisionCount,
            repositoryURL
        )
    }
}
