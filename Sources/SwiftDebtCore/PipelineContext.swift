/// The assessed consequence of a change entering a pipeline.
public enum PipelineRisk: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
    case critical
}

/// The event that requested a pipeline.
public enum PipelineTrigger: String, Codable, Equatable, Sendable {
    case pullRequest
    case scheduled
}

/// Whether the affected surface is established before planning.
public enum PipelineImpact: String, Codable, Equatable, Sendable {
    case known
    case uncertain
}

/// Inputs used to derive a deterministic pipeline plan.
public struct PipelineContext: Codable, Equatable, Sendable {
    public let risk: PipelineRisk
    public let trigger: PipelineTrigger
    public let impact: PipelineImpact

    public init(risk: PipelineRisk, trigger: PipelineTrigger, impact: PipelineImpact) {
        self.risk = risk
        self.trigger = trigger
        self.impact = impact
    }
}

/// A kind of verification that can be requested by a pipeline plan.
public enum PipelineCheck: String, Codable, CaseIterable, Equatable, Sendable {
    case staticAnalysis
    case architecture
    case unit
    case integration
    case regression
    case fullRegression
    case endToEnd
    case property
    case mutation
    case dynamicAnalysis
    case dependencies
}

/// A planned check and whether its evidence is required for a passing verdict.
public struct PipelineRequirement: Codable, Equatable, Sendable {
    public let check: PipelineCheck
    public let required: Bool
    public let reason: String

    public init(check: PipelineCheck, required: Bool, reason: String) {
        self.check = check
        self.required = required
        self.reason = reason
    }
}

/// The canonical checks selected for a specific pipeline context and policy revision.
public struct PipelinePlan: Codable, Equatable, Sendable {
    static let currentPolicyRevision = 1

    private enum CodingKeys: String, CodingKey {
        case policyRevision
        case context
        case requirements
    }

    public let policyRevision: Int
    public let context: PipelineContext
    public let requirements: [PipelineRequirement]

    init(
        policyRevision: Int,
        context: PipelineContext,
        requirements: [PipelineRequirement]
    ) {
        self.policyRevision = policyRevision
        self.context = context
        self.requirements = requirements
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            policyRevision: try values.decode(Int.self, forKey: .policyRevision),
            context: try values.decode(PipelineContext.self, forKey: .context),
            requirements: try values.decode([PipelineRequirement].self, forKey: .requirements)
        )
        guard isCanonical else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "Pipeline plan does not match the canonical policy for its context."
                ))
        }
    }

    var isCanonical: Bool {
        policyRevision == Self.currentPolicyRevision
            && requirements == PipelinePlanner.plan(context: context).requirements
    }
}
