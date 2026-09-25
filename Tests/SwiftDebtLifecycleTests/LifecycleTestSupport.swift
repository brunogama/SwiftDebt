import CryptoKit
import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax
import SwiftSyntax

enum TestRuleMode: Sendable {
    case committed(Int)
    case repeated(Int)
    case failed
}

struct LifecycleRuleV1: DebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.test"),
        id: RuleID(validated: "lifecycle")
    )
    static let metadata = RuleMetadata(
        name: "Lifecycle fixture",
        defaultSeverity: .warning,
        remediation: "Fixture only."
    )
    static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Emits the configured number of fixture Detections.",
        rationale: "Exercises lifecycle behavior through the R1 RuleEngine."
    )

    let mode: TestRuleMode

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        try emitFixtureDetections(mode: mode, context: context, emit: emit)
    }
}

struct LifecycleRuleV2: DebtRule {
    static let identity = LifecycleRuleV1.identity
    static let metadata = LifecycleRuleV1.metadata
    static let contract = RuleContract(
        semanticRevision: revisionTwo,
        semantics: "Changes the fixture Detection meaning.",
        rationale: "Exercises fail-closed Semantic Revision behavior."
    )

    let mode: TestRuleMode

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        try emitFixtureDetections(mode: mode, context: context, emit: emit)
    }
}

struct AlwaysFailingRule: DebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "swiftdebt.test"),
        id: RuleID(validated: "always-failing")
    )
    static let metadata = RuleMetadata(
        name: "Always failing fixture",
        defaultSeverity: .warning,
        remediation: "Fixture only."
    )
    static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Always fails without committing buffered Detections.",
        rationale: "Exercises independent Atomic Observation outcomes."
    )

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        throw FixtureRuleError.deliberate
    }
}

private enum FixtureRuleError: Error {
    case deliberate
    case insufficientTokens
}

private let revisionTwo: SemanticRevision = {
    guard let revision = SemanticRevision(2) else {
        preconditionFailure("Two is a valid Semantic Revision.")
    }
    return revision
}()

private func emitFixtureDetections(
    mode: TestRuleMode,
    context: AnalysisContext,
    emit: DetectionEmitter
) throws {
    switch mode {
    case .failed:
        throw FixtureRuleError.deliberate
    case .repeated(let count):
        let tokens = Array(context.sourceFile.tokens(viewMode: .sourceAccurate))
        guard let token = tokens.first else { throw FixtureRuleError.insufficientTokens }
        for index in 0..<count {
            emit(at: token, message: "Lifecycle repeated fixture Detection \(index + 1).")
        }
    case .committed(let count):
        let tokens = Array(context.sourceFile.tokens(viewMode: .sourceAccurate))
        guard tokens.count >= count else { throw FixtureRuleError.insufficientTokens }
        for index in 0..<count {
            emit(at: tokens[index], message: "Lifecycle fixture Detection \(index + 1).")
        }
    }
}

func makeObservation(
    id: String,
    lineage: String = "main",
    sequence: UInt,
    predecessor: String? = nil,
    scope: ObservationScope = .repository,
    configurationFingerprint: String = "configuration-v1",
    capabilities: [SnapshotCapability] = [],
    sourceIdentity: SnapshotSourceIdentity? = nil,
    engineVersion: String = "test-engine",
    source: String = "let first = 1\nlet second = 2\n",
    rules: [any DebtRule]
) throws -> ObservationSnapshot {
    let analysis = try RuleEngine().analyze(
        [SourceUnit(path: "Sources/Input.swift", content: source)],
        using: rules
    )
    let observedSourceIdentity = try sourceIdentity ?? .contentDigest(lifecycleDigest(for: source))
    return try ObservationSnapshot(
        id: SnapshotID(id),
        provenance: SnapshotProvenance(
            sourceIdentity: observedSourceIdentity,
            scope: scope,
            configurationFingerprint: lifecycleDigest(for: configurationFingerprint),
            capabilities: capabilities,
            engineVersion: engineVersion,
            lineage: LineagePosition(
                lineageID: LineageID(lineage),
                sequence: sequence,
                predecessorSnapshotID: try predecessor.map(SnapshotID.init)
            )
        ),
        analysis: analysis
    )
}

func lifecycleDigest(for value: String) throws -> LifecycleDigest {
    let value = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    return try LifecycleDigest(value: value)
}

func artifactJSONObject(at url: URL) throws -> [String: Any] {
    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    guard let object = value as? [String: Any] else {
        throw LifecycleContractError.invalidArtifact("Expected a JSON object fixture.")
    }
    return object
}

func lifecycleJSONData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

final class TemporaryLifecycleArtifact {
    let directory: URL
    let url: URL

    init() throws {
        directory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: FileManager.default.temporaryDirectory,
            create: true
        )
        url = directory.appendingPathComponent("lifecycle.json")
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
