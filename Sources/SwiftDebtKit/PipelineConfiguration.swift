import SwiftDebtCore

/// Binds one planned check to a directly launched executable and its arguments.
public struct PipelineCommand: Codable, Sendable {
    /// The check whose result this command supplies.
    public let check: PipelineCheck
    /// An absolute executable path; the runner does not perform shell expansion.
    public let executable: String
    /// Literal arguments passed to the executable.
    public let arguments: [String]
    /// The direct process deadline, validated as finite and within (0, 86400].
    public let timeoutSeconds: Double

    /// Creates a command binding. ``PipelineService`` validates it before execution.
    public init(
        check: PipelineCheck,
        executable: String,
        arguments: [String] = [],
        timeoutSeconds: Double = 600
    ) {
        self.check = check
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }
}

/// Explicit policy inputs and trusted executable bindings for a local run.
public struct PipelineConfiguration: Codable, Sendable {
    /// The configuration format version. The service currently supports version 1.
    public let schemaVersion: Int
    /// Declared risk, trigger, and impact certainty used by the planner.
    public let context: PipelineContext
    /// Unique command bindings. Unbound planned checks produce unavailable evidence.
    public let commands: [PipelineCommand]

    /// Creates configuration without executing or validating commands.
    public init(
        schemaVersion: Int = 1,
        context: PipelineContext,
        commands: [PipelineCommand]
    ) {
        self.schemaVersion = schemaVersion
        self.context = context
        self.commands = commands
    }
}

/// A local execution receipt containing a canonical plan and normalized evidence.
///
/// Decoding validates consistency with the current policy and recomputes the
/// verdict. A receipt does not authenticate assertions or prove finding resolution.
public struct PipelineRunReport: Codable, Sendable {
    /// The report format version, independent of the plan's policy revision.
    public let schemaVersion: Int
    /// The policy selected before execution.
    public let plan: PipelinePlan
    /// Results in plan order and the verdict derived from required checks.
    public let evaluation: PipelineEvaluation

    init(
        schemaVersion: Int,
        plan: PipelinePlan,
        evaluation: PipelineEvaluation
    ) {
        self.schemaVersion = schemaVersion
        self.plan = plan
        self.evaluation = evaluation
    }

    /// Decodes a receipt, rejecting unsupported schemas or contradictory evidence.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion, in: values, debugDescription: "Unsupported report schema")
        }
        let plan = try values.decode(PipelinePlan.self, forKey: .plan)
        let snapshot = try values.decode(EvaluationSnapshot.self, forKey: .evaluation)
        let evaluation = PipelineEvaluator.evaluate(plan: plan, results: snapshot.results)
        guard evaluation.verdict == snapshot.verdict, evaluation.results == snapshot.results else {
            throw DecodingError.dataCorruptedError(
                forKey: .evaluation, in: values,
                debugDescription: "Report evaluation does not match its plan and evidence")
        }
        self.init(schemaVersion: schemaVersion, plan: plan, evaluation: evaluation)
    }

    private struct EvaluationSnapshot: Decodable {
        let verdict: PipelineVerdict
        let results: [PipelineCheckResult]
    }
}
