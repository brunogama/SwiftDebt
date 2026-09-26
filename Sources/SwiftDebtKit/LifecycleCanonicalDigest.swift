import Foundation
import SwiftDebtCore
import SwiftDebtLifecycle

enum LifecycleCanonicalDigest {
    static func sourceUnits(_ sources: [SourceUnit]) throws -> LifecycleDigest {
        var input = LifecycleDigestInput()
        input.append("swiftdebt-lifecycle-source-v1")
        let ordered = sources.sorted { lhs, rhs in
            lhs.path == rhs.path ? lhs.module < rhs.module : lhs.path < rhs.path
        }
        input.append(UInt64(ordered.count))
        for source in ordered {
            input.append(source.path)
            input.append(source.module)
            input.append(source.content)
        }
        return try LifecycleDigest(value: input.hexDigest())
    }

    static func configuration(
        analysis: AnalysisSnapshot,
        capture: LifecycleAnalysisCapture
    ) throws -> LifecycleDigest {
        try effectiveConfiguration(
            analysis: analysis,
            selectionKind: capture.selectionKind,
            exclusions: capture.exclusions,
            maximumFileBytes: capture.maximumFileBytes
        ).fingerprint()
    }

    static func configuration(
        analysis: AnalysisSnapshot,
        selectionKind: LifecycleSelectionKind,
        exclusions: [String],
        maximumFileBytes: Int
    ) throws -> LifecycleDigest {
        try effectiveConfiguration(
            analysis: analysis,
            selectionKind: selectionKind,
            exclusions: exclusions,
            maximumFileBytes: maximumFileBytes
        ).fingerprint()
    }

    static func effectiveConfiguration(
        analysis: AnalysisSnapshot,
        capture: LifecycleAnalysisCapture
    ) throws -> LifecycleEffectiveConfiguration {
        try effectiveConfiguration(
            analysis: analysis,
            selectionKind: capture.selectionKind,
            exclusions: capture.exclusions,
            maximumFileBytes: capture.maximumFileBytes
        )
    }

    static func effectiveConfiguration(
        analysis: AnalysisSnapshot,
        selectionKind: LifecycleSelectionKind,
        exclusions: [String],
        maximumFileBytes: Int
    ) throws -> LifecycleEffectiveConfiguration {
        let kind: SourceSelectionKind =
            switch selectionKind {
            case .directory: .directory
            case .file: .file
            case .manifest: .manifest
            }
        return try LifecycleEffectiveConfiguration(
            sourceSelectionKind: kind,
            excludedSourcePrefixes: exclusions,
            maximumFileBytes: maximumFileBytes,
            selectedRuleIdentities: analysis.ruleDescriptors.map(\.identity)
        )
    }

    static func snapshotID(
        sourceIdentity: SnapshotSourceIdentity,
        scope: ObservationScope,
        configuration: LifecycleDigest,
        rules: [RuleDescriptor],
        capabilities: [SnapshotCapability],
        engineVersion: String,
        sourceSelection: SourceSelectionEvidence? = nil,
        sourceRenames: [SourceRenameEvidence] = [],
        sourceDeletions: [SourceDeletionEvidence] = []
    ) throws -> SnapshotID {
        var input = LifecycleDigestInput()
        input.append("swiftdebt-lifecycle-snapshot-id-v2")
        append(sourceIdentity, to: &input)
        append(scope, to: &input)
        input.append(configuration.algorithm.rawValue)
        input.append(configuration.value)
        let orderedRules = rules.sorted { $0.identity.description < $1.identity.description }
        input.append(UInt64(orderedRules.count))
        for rule in orderedRules {
            input.append(rule.identity.description)
            input.append(rule.semanticRevision.rawValue.description)
            input.append(UInt64(rule.contract.compatibilityDeclarations.count))
            for declaration in rule.contract.compatibilityDeclarations {
                input.append(declaration.fromRevision.rawValue.description)
                input.append(UInt64(declaration.supportedClaims.count))
                for claim in declaration.supportedClaims { input.append(claim.rawValue) }
                input.append(declaration.rationale)
            }
            let configurationDeclarations = rule.contract.configurationCompatibilityDeclarations
            if !configurationDeclarations.isEmpty {
                input.append("configuration-compatibility-v1")
                input.append(UInt64(configurationDeclarations.count))
                for declaration in configurationDeclarations {
                    input.append(declaration.fromRevision.rawValue.description)
                    input.append(UInt64(declaration.supportedClaims.count))
                    for claim in declaration.supportedClaims { input.append(claim.rawValue) }
                    input.append(UInt64(declaration.conditions.count))
                    for condition in declaration.conditions { input.append(condition.rawValue) }
                    input.append(declaration.testEvidence.identifier)
                    input.append(declaration.testEvidence.summary)
                    input.append(declaration.rationale)
                }
            }
        }
        input.append(engineVersion)
        input.append(UInt64(capabilities.count))
        for capability in capabilities.sorted(by: { $0.name < $1.name }) {
            input.append(capability.name)
            switch capability.state {
            case .available:
                input.append("available")
            case .unavailable(let reason):
                input.append("unavailable")
                append(reason, to: &input)
            case .ambiguous(let reason):
                input.append("ambiguous")
                append(reason, to: &input)
            }
        }
        if let sourceSelection {
            input.append("source-selection-v1")
            input.append(sourceSelection.kind.rawValue)
            input.append(sourceSelection.repositoryRelativeRoot?.rawValue ?? ".")
            input.append(UInt64(sourceSelection.excludedPathPrefixes.count))
            for exclusion in sourceSelection.excludedPathPrefixes {
                input.append(exclusion.rawValue)
            }
        }
        input.append(UInt64(sourceRenames.count))
        for rename in sourceRenames.sorted(by: sourceRenameOrder) {
            input.append(rename.priorSourcePath.rawValue)
            input.append(rename.currentSourcePath.rawValue)
            input.append(rename.similarityPercentage.description)
        }
        if !sourceDeletions.isEmpty {
            input.append("source-deletions-v1")
            input.append(UInt64(sourceDeletions.count))
            for deletion in sourceDeletions.sorted(by: sourceDeletionOrder) {
                input.append(deletion.priorSourcePath.rawValue)
            }
        }
        return try SnapshotID("snapshot-\(input.hexDigest())")
    }

    private static func append(_ identity: SnapshotSourceIdentity, to input: inout LifecycleDigestInput) {
        switch identity {
        case .git(let revision, let state, let digest):
            input.append("git")
            input.append(revision.rawValue)
            input.append(state.rawValue)
            input.append(digest.value)
        case .contentDigest(let digest):
            input.append("content-digest")
            input.append(digest.value)
        case .unavailable(let reason):
            input.append("unavailable")
            append(reason, to: &input)
        }
    }

    private static func append(_ scope: ObservationScope, to input: inout LifecycleDigestInput) {
        switch scope {
        case .repository:
            input.append("repository")
        case .partial(let reason):
            input.append("partial")
            append(reason, to: &input)
        }
    }

    private static func append(_ reason: LifecycleReason, to input: inout LifecycleDigestInput) {
        input.append(reason.code)
        input.append(reason.message)
    }
}
