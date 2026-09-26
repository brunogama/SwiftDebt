import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax
import Testing

@Suite("R3 effective-configuration contract")
struct EffectiveConfigurationContractTests {
    @Test("FR-18 cross-revision configuration changes require both declarations")
    func crossRevisionRequiresBothDeclarations() throws {
        let compatibleFixture = try TemporaryLifecycleArtifact()
        let compatibleStore = LifecycleArtifactStore(artifactURL: compatibleFixture.url)
        let prior = try makeEffectiveConfigurationObservation(
            id: "config-cross-revision-v1",
            sequence: 1,
            maximumFileBytes: 4_096,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let current = try makeEffectiveConfigurationObservation(
            id: "config-cross-revision-v2",
            sequence: 2,
            predecessor: prior.id.rawValue,
            maximumFileBytes: 8_192,
            rules: [LifecycleRuleV2ContinuityAndConfigurationCompatible(mode: .committed(1))]
        )
        _ = try compatibleStore.ingest(prior)
        _ = try compatibleStore.ingest(current)

        let compatibleFinding = try #require(compatibleStore.load().findings.first)
        let compatibleComparison = try #require(
            compatibleFinding.events.last?.semanticComparisons.first
        )
        #expect(compatibleFinding.events.map(\.transition.kind) == [.opened, .observed])
        #expect(compatibleComparison.decision == .compatible)
        #expect(compatibleComparison.compatibilityDeclaration != nil)
        #expect(compatibleComparison.configurationCompatibilityDeclaration != nil)
        let authoritativeRule = try #require(current.rules.first)
        #expect(authoritativeRule.configurationCompatibilityDeclarations.count == 1)
        #expect(
            SnapshotRule(
                identity: authoritativeRule.identity,
                semanticRevision: authoritativeRule.semanticRevision
            ).configurationCompatibilityDeclarations.isEmpty
        )

        let semanticOnlyFixture = try TemporaryLifecycleArtifact()
        let semanticOnlyStore = LifecycleArtifactStore(artifactURL: semanticOnlyFixture.url)
        let semanticOnlyPrior = try makeEffectiveConfigurationObservation(
            id: "config-semantic-only-v1",
            sequence: 1,
            maximumFileBytes: 4_096,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let semanticOnlyCurrent = try makeEffectiveConfigurationObservation(
            id: "config-semantic-only-v2",
            sequence: 2,
            predecessor: semanticOnlyPrior.id.rawValue,
            maximumFileBytes: 8_192,
            rules: [LifecycleRuleV2ContinuityCompatible(mode: .committed(1))]
        )
        _ = try semanticOnlyStore.ingest(semanticOnlyPrior)
        _ = try semanticOnlyStore.ingest(semanticOnlyCurrent)

        let semanticOnlyArtifact = try semanticOnlyStore.load()
        let semanticOnlyFinding = try #require(semanticOnlyArtifact.findings.first)
        let semanticOnlyEvent = try #require(semanticOnlyFinding.events.last)
        guard case .unverified(let reasons) = semanticOnlyEvent.transition else {
            Issue.record("Expected missing configuration authority to block continuity")
            return
        }
        #expect(reasons.map(\.code).contains("configuration-compatibility-not-declared"))
        #expect(semanticOnlyEvent.semanticComparisons.first?.compatibilityDeclaration != nil)
        #expect(
            semanticOnlyEvent.semanticComparisons.first?.configurationCompatibilityDeclaration == nil
        )
    }

    @Test("Configuration declarations do not relax engine compatibility")
    func engineVersionChangeStillBlocks() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let prior = try makeEffectiveConfigurationObservation(
            id: "config-engine-prior",
            sequence: 1,
            maximumFileBytes: 4_096,
            engineVersion: "engine-1",
            source: Self.detectedSource,
            rules: [ForceTryRule()]
        )
        let current = try makeEffectiveConfigurationObservation(
            id: "config-engine-current",
            sequence: 2,
            predecessor: prior.id.rawValue,
            maximumFileBytes: 8_192,
            engineVersion: "engine-2",
            source: Self.resolvedSource,
            rules: [ForceTryRule()]
        )
        _ = try store.ingest(prior)
        _ = try store.ingest(current)

        let finding = try #require(store.load().findings.first)
        let event = try #require(finding.events.last)
        guard case .unverified(let reasons) = event.transition else {
            Issue.record("Expected the engine change to block resolution")
            return
        }
        #expect(finding.lifecycleState == .open)
        #expect(reasons.map(\.code).contains("engine-incomparable"))
        #expect(event.semanticComparisons.first?.configurationCompatibilityDeclaration != nil)
        #expect(event.semanticComparisons.first?.decision == .blocked)
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }

        """

    private static let resolvedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try? load() }

        """
}

private func makeEffectiveConfigurationObservation(
    id: String,
    sequence: UInt,
    predecessor: String? = nil,
    maximumFileBytes: Int,
    engineVersion: String = "test-engine",
    source: String = "let first = 1\nlet second = 2\n",
    rules: [any DebtRule]
) throws -> ObservationSnapshot {
    let sourceUnit = SourceUnit(path: "Sources/Input.swift", content: source)
    let analysis = try RuleEngine().analyze([sourceUnit], using: rules)
    let configuration = try LifecycleEffectiveConfiguration(
        sourceSelectionKind: .directory,
        excludedSourcePrefixes: [],
        maximumFileBytes: maximumFileBytes,
        selectedRuleIdentities: analysis.ruleDescriptors.map(\.identity)
    )
    return try ObservationSnapshot(
        id: SnapshotID(id),
        provenance: SnapshotProvenance(
            sourceIdentity: .contentDigest(lifecycleDigest(for: source)),
            scope: .repository,
            configurationFingerprint: configuration.fingerprint(),
            effectiveConfiguration: configuration,
            engineVersion: engineVersion,
            lineage: LineagePosition(
                lineageID: LineageID("main"),
                sequence: sequence,
                predecessorSnapshotID: try predecessor.map(SnapshotID.init)
            )
        ),
        analysis: analysis
    )
}
