import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public enum LifecycleStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingArtifact(String)
    case lockFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case .missingArtifact(let path):
            "Lifecycle artifact does not exist: \(path)"
        case .lockFailed(let path, let reason):
            "Unable to lock lifecycle artifact \(path): \(reason)"
        case .readFailed(let path, let reason):
            "Unable to read lifecycle artifact \(path): \(reason)"
        case .writeFailed(let path, let reason):
            "Unable to write lifecycle artifact \(path): \(reason)"
        }
    }
}

public struct LifecycleArtifactStore: Sendable {
    public let artifactURL: URL
    public let generatorVersion: String

    public init(artifactURL: URL, generatorVersion: String = "SwiftDebt") {
        self.artifactURL = artifactURL.standardizedFileURL
        self.generatorVersion = generatorVersion
    }

    public func load() throws -> LifecycleArtifact {
        guard FileManager.default.fileExists(atPath: artifactURL.path) else {
            throw LifecycleStoreError.missingArtifact(artifactURL.path)
        }
        do {
            let data = try Data(contentsOf: artifactURL)
            return try JSONDecoder().decode(LifecycleArtifact.self, from: data)
        } catch {
            throw LifecycleStoreError.readFailed(path: artifactURL.path, reason: String(describing: error))
        }
    }

    public func ingest(_ snapshot: ObservationSnapshot) throws -> LifecycleReduction {
        try ingestLocked { _ in snapshot }
    }

    package func ingest(
        buildingSnapshot buildSnapshot: (LifecycleArtifact?) throws -> ObservationSnapshot
    ) throws -> LifecycleReduction {
        try ingestLocked(buildSnapshot)
    }

    package func recordIntroduction(
        _ evidence: IntroductionHistoryEvidence,
        for findingID: FindingID
    ) throws -> IntroductionRecording {
        try withExclusiveLock {
            let artifact = try load()
            guard let finding = artifact.finding(id: findingID) else {
                throw LifecycleContractError.missingFinding(findingID.rawValue)
            }
            if let existing = artifact.introductionConclusions(for: findingID)
                .first(where: { $0.evidence == evidence })
            {
                return IntroductionRecording(
                    artifact: artifact,
                    conclusion: existing,
                    status: .alreadyPresent
                )
            }

            let attempt = UInt(artifact.introductionConclusions(for: findingID).count + 1)
            let conclusion = try IntroductionConclusionEvaluator().make(
                finding: finding,
                attempt: attempt,
                evidence: evidence,
                artifact: artifact
            )
            var conclusions = artifact.introductionConclusions
            conclusions.append(conclusion)
            let updated = try LifecycleArtifact(
                schemaVersion: artifact.schemaVersion,
                reportKind: artifact.reportKind,
                generatorVersion: artifact.generatorVersion,
                snapshots: artifact.snapshots,
                findings: artifact.findings,
                unresolvedDetections: artifact.unresolvedDetections,
                processedSnapshotIDs: artifact.processedSnapshotIDs,
                lineageHeads: artifact.lineageHeads,
                introductionConclusions: conclusions
            )
            try write(updated)
            return IntroductionRecording(
                artifact: updated,
                conclusion: conclusion,
                status: .accepted
            )
        }
    }

    private func ingestLocked(
        _ buildSnapshot: (LifecycleArtifact?) throws -> ObservationSnapshot
    ) throws -> LifecycleReduction {
        let directory = artifactURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LifecycleStoreError.writeFailed(path: artifactURL.path, reason: String(describing: error))
        }
        return try withExclusiveLock {
            let existingArtifact = FileManager.default.fileExists(atPath: artifactURL.path) ? try load() : nil
            let snapshot = try buildSnapshot(existingArtifact)
            let artifact = try existingArtifact ?? LifecycleArtifact(generatorVersion: generatorVersion)
            let reduction = try LifecycleReducer().ingest(snapshot, into: artifact)
            if reduction.status == .accepted {
                try write(reduction.artifact)
            }
            return reduction
        }
    }

    public func canonicalData(for artifact: LifecycleArtifact) throws -> Data {
        try artifact.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(artifact)
        data.append(0x0A)
        return data
    }

    private func write(_ artifact: LifecycleArtifact) throws {
        do {
            try canonicalData(for: artifact).write(to: artifactURL, options: .atomic)
        } catch {
            throw LifecycleStoreError.writeFailed(path: artifactURL.path, reason: String(describing: error))
        }
    }

    private func withExclusiveLock<Result>(_ operation: () throws -> Result) throws -> Result {
        let lockPath = artifactURL.path + ".lock"
        let descriptor = open(lockPath, O_CREAT | O_RDWR, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else {
            throw LifecycleStoreError.lockFailed(path: lockPath, reason: systemErrorDescription())
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw LifecycleStoreError.lockFailed(path: lockPath, reason: systemErrorDescription())
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func systemErrorDescription() -> String {
        String(cString: strerror(errno))
    }
}

public enum IntroductionRecordingStatus: String, Codable, Equatable, Sendable {
    case accepted
    case alreadyPresent = "already-present"
}

public struct IntroductionRecording: Equatable, Sendable {
    public let artifact: LifecycleArtifact
    public let conclusion: IntroductionConclusion
    public let status: IntroductionRecordingStatus

    public init(
        artifact: LifecycleArtifact,
        conclusion: IntroductionConclusion,
        status: IntroductionRecordingStatus
    ) {
        self.artifact = artifact
        self.conclusion = conclusion
        self.status = status
    }
}
