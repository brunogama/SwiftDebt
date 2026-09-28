import Foundation
import SwiftDebtCore

/// One project-scope Detection produced by `UnsafeSwiftPMFlagsRule`.
///
/// Per ADR 0001 Q5 ("How do project-level Detections represent location?"):
/// project-scope Detections carry a manifest-relative location, never a
/// fabricated `SourceLocation`. `evidenceLocation.file`/`.line` stay `nil`
/// here on purpose - this Detection has no source span, only a manifest
/// path (`evidenceLocation.projectManifestPath`).
public struct ProjectManifestDetection: Codable, Hashable, Sendable {
    public let ruleIdentity: RuleIdentity
    public let evidenceLocation: EvidenceLocation
    public let targetName: String
    public let message: String

    public init(
        ruleIdentity: RuleIdentity,
        evidenceLocation: EvidenceLocation,
        targetName: String,
        message: String
    ) {
        precondition(
            evidenceLocation.file == nil && evidenceLocation.line == nil,
            "project-scope Detections must never carry a fabricated source location (ADR 0001 Q5)")
        self.ruleIdentity = ruleIdentity
        self.evidenceLocation = evidenceLocation
        self.targetName = targetName
        self.message = message
    }
}

/// `build.swiftpm-unsafe-flags` (research #71, addendum J/N-71): a SwiftPM
/// target declares `.unsafeFlags(...)` in its build settings. This is
/// project scope, not a source syntax rule (addendum J: "A
/// `PackageAnalysisContext` can expose manifest facts without contaminating
/// source-local rule APIs") - deterministic, because `dump-package` either
/// reports the setting or it does not.
public enum UnsafeSwiftPMFlagsRule {
    public static let definition = RuleDefinition(
        identity: RuleIdentity("build.swiftpm-unsafe-flags"),
        metadata: RuleMetadata(
            title: "SwiftPM target declares unsafe build flags",
            category: .build,
            provenance: [
                RuleProvenance(researchItem: 71, note: "addendum J/N-71: SwiftPM unsafeFlags")
            ],
            supportState: .supported
        ),
        scope: .project,
        mode: .deterministic,
        requirements: RuleRequirements([.packageManifest]),
        evidenceContract: EvidenceContract(
            required: .fact(
                EvidenceRequirement(key: "swiftpm.target.unsafeFlags", kind: .configuration))
        ),
        semanticRevision: 1
    )

    /// Evaluates the rule against already-extracted manifest facts,
    /// producing one Detection per target that declares `.unsafeFlags(...)`.
    ///
    /// `manifestPath` is carried verbatim into
    /// `EvidenceLocation.projectManifestPath`; this function never invents a
    /// `file`/`line` for a project-scope claim (ADR 0001 Q5).
    public static func detect(
        manifestPath: String,
        facts: PackageManifestFacts
    ) -> [ProjectManifestDetection] {
        facts.targets
            .filter(\.hasUnsafeFlags)
            .map { target in
                ProjectManifestDetection(
                    ruleIdentity: definition.identity,
                    evidenceLocation: EvidenceLocation(projectManifestPath: manifestPath),
                    targetName: target.targetName,
                    message: "Target '\(target.targetName)' declares unsafeFlags in its SwiftPM manifest settings."
                )
            }
    }
}
