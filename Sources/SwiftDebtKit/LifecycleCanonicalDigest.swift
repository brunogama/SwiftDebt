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
        var input = LifecycleDigestInput()
        input.append("swiftdebt-lifecycle-configuration-v1")
        input.append("source-discovery-policy-v1")
        input.append(capture.selectionKind.rawValue)
        input.append(capture.maximumFileBytes.description)
        input.append(UInt64(capture.exclusions.count))
        for exclusion in capture.exclusions { input.append(exclusion) }
        let rules = analysis.ruleDescriptors.sorted {
            $0.identity.description < $1.identity.description
        }
        input.append(UInt64(rules.count))
        for rule in rules {
            input.append(rule.identity.description)
            input.append(rule.semanticRevision.rawValue.description)
        }
        return try LifecycleDigest(value: input.hexDigest())
    }

    static func snapshotID(
        sourceIdentity: SnapshotSourceIdentity,
        scope: ObservationScope,
        configuration: LifecycleDigest,
        capabilities: [SnapshotCapability],
        engineVersion: String
    ) throws -> SnapshotID {
        var input = LifecycleDigestInput()
        input.append("swiftdebt-lifecycle-snapshot-id-v1")
        append(sourceIdentity, to: &input)
        append(scope, to: &input)
        input.append(configuration.algorithm.rawValue)
        input.append(configuration.value)
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
