import SwiftDebtLifecycle
import Testing

@Suite("R3 effective-configuration compatibility CLI acceptance")
struct EffectiveConfigurationCompatibilityCLIWorkflowTests {
    @Test("FR-17 a broader declared maximum-file-size configuration can prove absence")
    func nondecreasingMaximumFileBytesSupportsAbsence() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")

        let first = try analyze(fixture, maximumFileBytes: 4_096)
        #expect(first.status == 0)
        let opening = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let openingFinding = try #require(opening.findings.first)

        _ = try fixture.commit(source: Self.resolvedSource, message: "remove forced try")
        let second = try analyze(fixture, maximumFileBytes: 8_192)
        #expect(second.status == 0)

        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.finding(id: openingFinding.id))
        let resolution = try #require(finding.events.last)
        let comparison = try #require(
            resolution.semanticComparisons.first(where: { $0.claim == .absence })
        )

        #expect(finding.lifecycleState == .resolved)
        #expect(finding.evidenceState == .verifiedAbsent)
        #expect(comparison.decision == .compatible)
        #expect(comparison.priorRule.semanticRevision == comparison.currentRule.semanticRevision)
        #expect(comparison.priorConfigurationFingerprint != comparison.currentConfigurationFingerprint)

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.artifact.path, finding.id.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("maximum-file-bytes-nondecreasing"))
        #expect(explanation.standardOutput.contains("configuration-compatibility-declared"))
        #expect(
            explanation.standardOutput.contains(
                "EffectiveConfigurationCompatibilityCLIWorkflowTests.nondecreasingMaximumFileBytesSupportsAbsence"
            )
        )
    }

    @Test("FR-17 an absence declaration does not authorize continuity")
    func absenceDeclarationDoesNotAuthorizeContinuity() throws {
        let fixture = try TemporaryLifecycleGitRepository()
        _ = try fixture.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(fixture, maximumFileBytes: 4_096).status == 0)
        let opening = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let findingID = try #require(opening.findings.first?.id)

        _ = try fixture.commit(source: Self.movedDetectedSource, message: "move forced try")
        #expect(try analyze(fixture, maximumFileBytes: 8_192).status == 0)

        let artifact = try LifecycleArtifactStore(artifactURL: fixture.artifact).load()
        let finding = try #require(artifact.finding(id: findingID))
        let event = try #require(finding.events.last)
        guard case .unverified(let reasons) = event.transition else {
            Issue.record("Expected continuity to remain unverified")
            return
        }
        let comparison = try #require(event.semanticComparisons.first)
        #expect(finding.lifecycleState == .open)
        #expect(artifact.findings.count == 1)
        #expect(artifact.unresolvedDetections.count == 1)
        #expect(comparison.claim == .continuity)
        #expect(comparison.decision == .blocked)
        #expect(comparison.configurationCompatibilityDeclaration == nil)
        #expect(reasons.map(\.code).contains("configuration-continuity-not-declared"))
        #expect(reasons.map(\.code).contains("configuration-maximum-file-bytes-not-declared"))

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", fixture.artifact.path, finding.id.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("configuration-continuity-not-declared"))
        #expect(explanation.standardOutput.contains("continuity revisions=1->1 blocked"))
    }

    @Test("FR-17 reverse and undeclared configuration changes remain blocked")
    func reverseAndUndeclaredChangesFailClosed() throws {
        let reverse = try TemporaryLifecycleGitRepository()
        _ = try reverse.commit(source: Self.detectedSource, message: "add forced try")
        #expect(try analyze(reverse, maximumFileBytes: 8_192).status == 0)
        let reverseOpening = try LifecycleArtifactStore(artifactURL: reverse.artifact).load()
        let reverseFindingID = try #require(reverseOpening.findings.first?.id)
        _ = try reverse.commit(source: Self.resolvedSource, message: "remove forced try")
        #expect(try analyze(reverse, maximumFileBytes: 4_096).status == 0)

        let reverseArtifact = try LifecycleArtifactStore(artifactURL: reverse.artifact).load()
        let reverseFinding = try #require(reverseArtifact.finding(id: reverseFindingID))
        let reverseEvent = try #require(reverseFinding.events.last)
        guard case .unverified(let reverseReasons) = reverseEvent.transition else {
            Issue.record("Expected a decreasing file-size limit to remain unverified")
            return
        }
        #expect(reverseFinding.lifecycleState == .open)
        #expect(reverseReasons.map(\.code).contains("configuration-compatibility-direction-blocked"))
        #expect(reverseEvent.semanticComparisons.first?.configurationCompatibilityDeclaration != nil)

        let undeclared = try TemporaryLifecycleGitRepository()
        _ = try undeclared.commit(source: Self.forceCastSource, message: "add forced cast")
        #expect(try analyze(undeclared, maximumFileBytes: 4_096).status == 0)
        let undeclaredOpening = try LifecycleArtifactStore(artifactURL: undeclared.artifact).load()
        let undeclaredFindingID = try #require(undeclaredOpening.findings.first?.id)
        _ = try undeclared.commit(source: Self.resolvedForceCastSource, message: "remove forced cast")
        #expect(try analyze(undeclared, maximumFileBytes: 8_192).status == 0)

        let undeclaredArtifact = try LifecycleArtifactStore(artifactURL: undeclared.artifact).load()
        let undeclaredFinding = try #require(undeclaredArtifact.finding(id: undeclaredFindingID))
        let undeclaredEvent = try #require(undeclaredFinding.events.last)
        guard case .unverified(let undeclaredReasons) = undeclaredEvent.transition else {
            Issue.record("Expected an undeclared configuration change to remain unverified")
            return
        }
        #expect(undeclaredFinding.lifecycleState == .open)
        #expect(undeclaredReasons.map(\.code).contains("configuration-compatibility-not-declared"))
        #expect(undeclaredReasons.map(\.code).contains("configuration-maximum-file-bytes-not-declared"))
        #expect(undeclaredEvent.semanticComparisons.first?.configurationCompatibilityDeclaration == nil)

        let explanation = try runLifecycleCLI([
            "lifecycle", "explain", undeclared.artifact.path, undeclaredFinding.id.rawValue,
        ])
        #expect(explanation.status == 0)
        #expect(explanation.standardOutput.contains("configuration-maximum-file-bytes-not-declared"))
        #expect(explanation.standardOutput.contains("4096 -> 8192"))
    }

    private func analyze(
        _ fixture: TemporaryLifecycleGitRepository,
        maximumFileBytes: Int
    ) throws -> LifecycleCLIRunResult {
        try runLifecycleCLI([
            "analyze", fixture.repository.path,
            "--format", "json",
            "--lifecycle-artifact", fixture.artifact.path,
            "--max-file-bytes", String(maximumFileBytes),
            "--jobs", "2",
        ])
    }

    private static let detectedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try! load() }

        """

    private static let resolvedSource = """
        func load() throws -> Int { 1 }
        func run() { _ = try? load() }

        """

    private static let movedDetectedSource = """
        func load() throws -> Int { 1 }

        func run() { _ = try! load() }

        """

    private static let forceCastSource = """
        func cast(_ value: Any) { _ = value as! String }

        """

    private static let resolvedForceCastSource = """
        func cast(_ value: Any) { _ = value as? String }

        """
}
