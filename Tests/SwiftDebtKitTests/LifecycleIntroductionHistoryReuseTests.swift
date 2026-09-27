import SwiftDebtCore
import SwiftDebtLifecycle
import Testing

@testable import SwiftDebtKit

@Suite("Lifecycle introduction history reuse")
struct LifecycleIntroductionHistoryReuseTests {
    @Test("Only complete unambiguous observations with current severity are reusable")
    func incompleteConflictingAndStaleCandidatesMiss() throws {
        let sourcePath = try SourcePath("Sources/Input.swift")
        let descriptor = RuleDescriptor(
            identity: RuleIdentity(
                namespace: try #require(RuleNamespace("swiftdebt.test")),
                id: try #require(RuleID("reuse"))
            ),
            metadata: RuleMetadata(
                name: "Reuse fixture",
                defaultSeverity: .warning,
                remediation: "Fixture only."
            ),
            contract: RuleContract(
                semanticRevision: .initial,
                semantics: "Fixture semantics.",
                rationale: "Fixture only."
            )
        )
        let snapshotID = try SnapshotID("snapshot-reuse")
        let provenance = try SnapshotProvenance(
            sourceIdentity: .contentDigest(
                try LifecycleDigest(value: String(repeating: "a", count: 64))
            ),
            scope: .repository,
            configurationFingerprint: try LifecycleDigest(
                value: String(repeating: "b", count: 64)
            ),
            engineVersion: "test-engine",
            lineage: try LineagePosition(
                lineageID: LineageID("history-reuse"),
                sequence: 1
            )
        )
        let committed = try observation(
            id: snapshotID,
            provenance: provenance,
            descriptor: descriptor,
            sourcePath: sourcePath,
            outcome: .committed([])
        )
        let failed = try observation(
            id: snapshotID,
            provenance: provenance,
            descriptor: descriptor,
            sourcePath: sourcePath,
            outcome: .failed(reason: "fixture failure")
        )
        let unsupported = try observation(
            id: snapshotID,
            provenance: provenance,
            descriptor: descriptor,
            sourcePath: sourcePath,
            outcome: .unsupported(reason: "fixture unsupported")
        )
        let parseFailed = try observation(
            id: snapshotID,
            provenance: provenance,
            descriptor: descriptor,
            sourcePath: sourcePath,
            outcome: .parseFailed(diagnostics: [
                AnalysisDiagnostic(
                    severity: .error,
                    message: "fixture parse failure",
                    location: SourceLocation(file: sourcePath.rawValue, line: 1)
                )
            ])
        )
        let detected = try observation(
            id: snapshotID,
            provenance: provenance,
            descriptor: descriptor,
            sourcePath: sourcePath,
            outcome: .committed([
                try detection(descriptor: descriptor, sourcePath: sourcePath, severity: .warning)
            ])
        )
        let staleSeverity = try observation(
            id: snapshotID,
            provenance: provenance,
            descriptor: descriptor,
            sourcePath: sourcePath,
            outcome: .committed([
                try detection(descriptor: descriptor, sourcePath: sourcePath, severity: .error)
            ])
        )
        let identity = LifecycleIntroductionObservationIdentity(
            snapshotID: snapshotID,
            provenance: provenance,
            rules: committed.rules,
            sourcePaths: [sourcePath],
            defaultSeverities: [descriptor.identity: .warning]
        )

        #expect(identity.matchingObservation(among: [committed]) == committed)
        #expect(identity.matchingObservation(among: [committed, committed]) == committed)
        #expect(identity.matchingObservation(among: [failed]) == nil)
        #expect(identity.matchingObservation(among: [unsupported]) == nil)
        #expect(identity.matchingObservation(among: [parseFailed]) == nil)
        #expect(identity.matchingObservation(among: [staleSeverity]) == nil)
        #expect(identity.matchingObservation(among: [committed, detected]) == nil)
    }

    private func observation(
        id: SnapshotID,
        provenance: SnapshotProvenance,
        descriptor: RuleDescriptor,
        sourcePath: SourcePath,
        outcome: RuleAnalysisOutcome
    ) throws -> ObservationSnapshot {
        try ObservationSnapshot(
            id: id,
            provenance: provenance,
            analysis: AnalysisSnapshot(
                ruleDescriptors: [descriptor],
                selectedSourcePaths: [sourcePath],
                ruleResults: [
                    RuleAnalysisResult(
                        descriptor: descriptor,
                        sourcePath: sourcePath,
                        outcome: outcome
                    )
                ]
            )
        )
    }

    private func detection(
        descriptor: RuleDescriptor,
        sourcePath: SourcePath,
        severity: RuleSeverity
    ) throws -> Detection {
        Detection(
            ruleIdentity: descriptor.identity,
            semanticRevision: descriptor.semanticRevision,
            severity: severity,
            location: DetectionLocation(sourcePath: sourcePath, line: 1, column: 1),
            message: "fixture detection",
            structuralEvidence: DetectionStructuralEvidence(
                subjectDigest: try LifecycleDigest(
                    value: String(repeating: "c", count: 64)
                ),
                enclosingDeclarationDigest: nil
            )
        )
    }
}
