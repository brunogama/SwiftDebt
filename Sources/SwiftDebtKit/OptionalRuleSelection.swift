import SwiftDebtCore
import SwiftDebtLifecycle
import SwiftDebtSyntax

struct OptionalRuleSelection {
    let rules: [any DebtRule]
    let capabilities: [SnapshotCapability]

    static func make(
        request: AnalysisRequest,
        capture: LifecycleAnalysisCapture?,
        sources: [SourceUnit]
    ) throws -> OptionalRuleSelection {
        guard request.agedForceTry || request.gitBlameProviderPath == nil else {
            throw WorkspaceError("A Git blame provider requires the aged-force-try rule selection.")
        }
        var rules = BuiltInRuleCatalog.all
        var capabilities = [
            try SnapshotCapability(name: "syntax-analysis", state: .available)
        ]
        guard request.agedForceTry else {
            return OptionalRuleSelection(rules: rules, capabilities: capabilities)
        }

        let availability: GitBlameEvidenceAvailability
        if let provider = request.gitBlameProviderPath, let capture {
            availability = GitBlameEvidenceProvider().inspect(
                executablePath: provider,
                capture: capture,
                sources: sources
            )
        } else if request.gitBlameProviderPath == nil {
            availability = .unavailable(
                try LifecycleReason(
                    code: "git-blame-provider-omitted",
                    message:
                        "The selected aged-force-try rule requires --git-blame-provider with an absolute executable path."
                )
            )
        } else {
            availability = .unavailable(
                try LifecycleReason(
                    code: "git-blame-capture-unavailable",
                    message: "The selected aged-force-try rule could not capture source and Git provenance."
                )
            )
        }
        rules.append(AgedForceTryRule(availability: availability))
        capabilities.append(
            try SnapshotCapability(name: "git-blame-v1", state: availability.capabilityState)
        )
        return OptionalRuleSelection(rules: rules, capabilities: capabilities)
    }
}
