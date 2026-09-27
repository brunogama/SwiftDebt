import Foundation
import SwiftDebtLifecycle
import SwiftDebtSyntax
import Testing

@Suite("R3 Atomic Observation reason CLI acceptance")
struct AtomicObservationReasonCLIWorkflowTests {
    @Test("AT-8 a parse-failed successor names the recorded reason in both explanation formats")
    func parseFailureReasonIsExplained() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture).status == 0)
        let original = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(original.findings.first)

        _ = try fixture.commit(source: Self.unparseableSource, message: "break source parsing")
        let analysis = try analyze(fixture)
        #expect(analysis.status == 2, "\(analysis.standardError)")
        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let persistedFinding = try #require(artifact.finding(id: finding.id))
        #expect(persistedFinding.lifecycleState == .open)
        #expect(persistedFinding.evidenceState == .unverified)

        let arguments = ["lifecycle", "explain", fixture.artifact.path, finding.id.rawValue]
        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        #expect(text.status == 0)
        #expect(json.status == 0)
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        guard case .unverified(let reasons) = report.finding.events.last?.transition else {
            Issue.record("Expected the parse-failed successor to remain unverified")
            return
        }
        let latestEvent = try #require(persistedFinding.events.last)
        let latest = try #require(artifact.snapshot(id: latestEvent.snapshotID))
        let atomic = try #require(
            latest.atomicObservations.first { $0.rule.identity == finding.rule.identity }
        )
        guard case .notExecuted(let parseReason) = atomic.outcome else {
            Issue.record("Expected the affected Atomic Observation to record a parse failure")
            return
        }
        #expect(reasons == [parseReason])
        #expect(text.standardOutput.contains("\(parseReason.code): \(parseReason.message)"))
        #expect(!text.standardOutput.contains("atomic-observation-not-executed"))
    }

    @Test(
        "AT-1 and SM-4 incomplete observations keep the prior Finding unverified",
        arguments: AtomicReasonScenario.allCases
    )
    func incompleteObservationReasonIsExplained(_ scenario: AtomicReasonScenario) throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let first = try makeObservation(
            id: "reason-\(scenario.rawValue)-root",
            sequence: 1,
            source: Self.detectedSource,
            rules: [LifecycleRuleV1(mode: .committed(1)), ForceTryRule()]
        )
        let later = try laterObservation(for: scenario, predecessor: first.id)
        _ = try store.ingest(first)
        _ = try store.ingest(later)

        let artifact = try store.load()
        let finding = try #require(
            artifact.findings.first { $0.rule.identity == LifecycleRuleV1.identity }
        )
        #expect(finding.lifecycleState == .open)
        #expect(finding.evidenceState == .unverified)
        #expect(later.detections.contains { $0.rule.identity == ForceTryRule.identity })
        let companion = try #require(
            artifact.findings.first { $0.rule.identity == ForceTryRule.identity }
        )
        #expect(companion.events.last?.transition.kind == .observed)

        let arguments = ["lifecycle", "explain", fixture.url.path, finding.id.rawValue]
        let text = try runLifecycleCLI(arguments + ["--format", "text"])
        let json = try runLifecycleCLI(arguments + ["--format", "json"])
        #expect(text.status == 0)
        #expect(json.status == 0)
        let report = try JSONDecoder().decode(
            FindingExplanationReport.self,
            from: Data(json.standardOutput.utf8)
        )
        guard case .unverified(let reasons) = report.finding.events.last?.transition else {
            Issue.record("Expected \(scenario.rawValue) to keep the Finding unverified")
            return
        }
        #expect(reasons.map(\.code).contains(scenario.expectedReasonCode))
        if let atomic = later.atomicObservations.first(where: {
            $0.rule.identity == LifecycleRuleV1.identity
        }) {
            switch atomic.outcome {
            case .unsupported(let reason), .failed(let reason), .excluded(let reason):
                #expect(reasons.contains(reason))
            case .committed, .notExecuted:
                break
            }
        }
        for reason in reasons {
            #expect(text.standardOutput.contains("\(reason.code): \(reason.message)"))
        }
    }

    private func analyze(_ fixture: TemporaryLifecycleGitRepository) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
            "--jobs", "2",
        ])
    }

    private func laterObservation(
        for scenario: AtomicReasonScenario,
        predecessor: SnapshotID
    ) throws -> ObservationSnapshot {
        let id = "reason-\(scenario.rawValue)-child"
        let rules: [any DebtRule] =
            switch scenario {
            case .failed:
                [LifecycleRuleV1(mode: .failed), ForceTryRule()]
            case .unsupported:
                [UnsupportedLifecycleRule(), ForceTryRule()]
            case .excluded:
                [LifecycleRuleV1(mode: .committed(0)), ForceTryRule()]
            case .omitted:
                [ForceTryRule()]
            case .incomparable:
                [LifecycleRuleV2(mode: .committed(0)), ForceTryRule()]
            }
        let snapshot = try makeObservation(
            id: id,
            sequence: 2,
            predecessor: predecessor.rawValue,
            source: Self.detectedSource,
            rules: rules
        )
        guard scenario == .excluded else { return snapshot }
        let reason = try LifecycleReason(
            code: "source-excluded",
            message: "The SourceUnit was explicitly excluded from this rule."
        )
        let atomics = snapshot.atomicObservations.map { observation in
            guard observation.rule.identity == LifecycleRuleV1.identity else { return observation }
            return AtomicObservation(
                id: observation.id,
                rule: observation.rule,
                sourcePath: observation.sourcePath,
                outcome: .excluded(reason)
            )
        }
        return try ObservationSnapshot(
            id: snapshot.id,
            provenance: snapshot.provenance,
            rules: snapshot.rules,
            sources: snapshot.sources,
            atomicObservations: atomics,
            detections: snapshot.detections
        )
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }
        """

    private static let unparseableSource = """
        func load( {
        """
}

enum AtomicReasonScenario: String, CaseIterable, Sendable {
    case failed
    case unsupported
    case excluded
    case omitted
    case incomparable

    var expectedReasonCode: String {
        switch self {
        case .failed: "rule-failed"
        case .unsupported: "rule-unsupported"
        case .excluded: "source-excluded"
        case .omitted: "rule-omitted"
        case .incomparable: "semantic-revision-incomparable"
        }
    }
}

private struct UnsupportedLifecycleRule: DebtRule {
    static let identity = LifecycleRuleV1.identity
    static let metadata = LifecycleRuleV1.metadata
    static let contract = LifecycleRuleV1.contract

    func detect(in _: AnalysisContext, emit _: DetectionEmitter) throws {
        throw UnsupportedRuleAnalysis(reason: "The fixture lacks required semantic evidence.")
    }
}
