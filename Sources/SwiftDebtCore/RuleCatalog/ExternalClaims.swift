/// Rule Definitions cataloged straight from the research corpus with no
/// `RuleImplementation` at all (Invariant Q2, PRD FR-1/FR-3). These are the
/// `.externalRuntimeRequired` claims whose evidence lives outside anything
/// SwiftDebt can observe from source, symbols, or history - a CI/CD
/// pipeline's own runtime behavior (research #86-92, addendum J) - so the
/// catalog states the claim and stops there, rather than inventing a
/// detector against evidence it structurally cannot obtain.
public enum ExternalClaims {
    /// Research #88 (addendum J): a CI pipeline that resolves its Swift/Xcode
    /// toolchain from whatever the runner image happens to have, instead of
    /// pinning it (e.g. via `.swift-version`, an explicit `xcode-select`, or a
    /// pinned runner image tag), reproduces builds non-deterministically
    /// across runs and across contributors' machines. Observing this
    /// requires inspecting the CI provider's actual runtime environment at
    /// execution time - not something derivable from the repository's static
    /// contents - so it is cataloged with `mode: .external` and
    /// `supportState: .externalRuntimeRequired`, and deliberately has no
    /// `RuleImplementation`.
    public static let ciToolchainNotPinned = RuleDefinition(
        identity: RuleIdentity("ci.toolchain-not-pinned"),
        metadata: RuleMetadata(
            title: "CI pipeline lacks deterministic toolchain pinning",
            category: .ci,
            provenance: [
                RuleProvenance(
                    researchItem: 88,
                    note: "addendum J - CI/CD claims research #86-92; toolchain "
                        + "resolution is an external runtime fact, not a static one"
                )
            ],
            supportState: .externalRuntimeRequired
        ),
        scope: .external,
        mode: .external,
        requirements: RuleRequirements([.buildConfiguration]),
        evidenceContract: EvidenceContract(
            required: .fact(
                EvidenceRequirement(key: "ciRunnerToolchainResolution", kind: .configuration))
        ),
        semanticRevision: 1
    )
}
