/// The observed outcome of one configured pipeline command.
public enum PipelineCheckStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case unavailable
    case timedOut
}

/// Evidence reported for a planned pipeline check.
public struct PipelineCheckResult: Codable, Equatable, Sendable {
    public let check: PipelineCheck
    public let status: PipelineCheckStatus
    public let detail: String

    public init(check: PipelineCheck, status: PipelineCheckStatus, detail: String) {
        self.check = check
        self.status = status
        self.detail = detail
    }
}

/// The aggregate meaning of the available pipeline evidence.
public enum PipelineVerdict: String, Codable, Equatable, Sendable {
    case passed
    case failed
    case inconclusive
}

/// A normalized set of results and its aggregate verdict.
public struct PipelineEvaluation: Encodable, Equatable, Sendable {
    public let verdict: PipelineVerdict
    public let results: [PipelineCheckResult]

    init(verdict: PipelineVerdict, results: [PipelineCheckResult]) {
        self.verdict = verdict
        self.results = results
    }

    /// The CLI exit status associated with the verdict.
    public var exitStatus: Int32 {
        switch verdict {
        case .passed:
            0
        case .failed:
            1
        case .inconclusive:
            2
        }
    }
}
