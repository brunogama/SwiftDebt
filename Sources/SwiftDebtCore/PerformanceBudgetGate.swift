public struct PerformanceWorkloadIdentity: Codable, Equatable, Sendable {
    public let analyzer: String
    public let workloadFamily: String
    public let inputSHA256: String
    public let commandFingerprint: String
    public let analysisMode: String
    public let optionalContext: String

    public init(
        analyzer: String,
        workloadFamily: String,
        inputSHA256: String,
        commandFingerprint: String,
        analysisMode: String,
        optionalContext: String
    ) {
        self.analyzer = analyzer
        self.workloadFamily = workloadFamily
        self.inputSHA256 = inputSHA256
        self.commandFingerprint = commandFingerprint
        self.analysisMode = analysisMode
        self.optionalContext = optionalContext
    }
}

public struct PerformanceBenchmarkResult: Codable, Equatable, Sendable {
    public let workload: PerformanceWorkloadIdentity
    public let wallClockSecondsMedian: Double
    public let peakMemoryBytesMedian: UInt64

    public init(
        workload: PerformanceWorkloadIdentity,
        wallClockSecondsMedian: Double,
        peakMemoryBytesMedian: UInt64
    ) {
        self.workload = workload
        self.wallClockSecondsMedian = wallClockSecondsMedian
        self.peakMemoryBytesMedian = peakMemoryBytesMedian
    }
}

public struct PerformanceRegressionBudget: Codable, Equatable, Sendable {
    public let name: String
    public let maximumWallClockRegressionPercent: Double
    public let maximumPeakMemoryRegressionPercent: Double
    public let maximumWallClockRegressionSeconds: Double

    public init(
        name: String,
        maximumWallClockRegressionPercent: Double,
        maximumPeakMemoryRegressionPercent: Double,
        maximumWallClockRegressionSeconds: Double = 0
    ) {
        self.name = name
        self.maximumWallClockRegressionPercent = maximumWallClockRegressionPercent
        self.maximumPeakMemoryRegressionPercent = maximumPeakMemoryRegressionPercent
        self.maximumWallClockRegressionSeconds = maximumWallClockRegressionSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case maximumWallClockRegressionPercent
        case maximumPeakMemoryRegressionPercent
        case maximumWallClockRegressionSeconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        maximumWallClockRegressionPercent = try container.decode(
            Double.self,
            forKey: .maximumWallClockRegressionPercent
        )
        maximumPeakMemoryRegressionPercent = try container.decode(
            Double.self,
            forKey: .maximumPeakMemoryRegressionPercent
        )
        maximumWallClockRegressionSeconds =
            try container.decodeIfPresent(
                Double.self,
                forKey: .maximumWallClockRegressionSeconds
            ) ?? 0
    }
}

public struct PerformanceBudgetEvaluation: Codable, Equatable, Sendable {
    public let comparable: Bool
    public let passed: Bool
    public let wallClockRegressionPercent: Double?
    public let peakMemoryRegressionPercent: Double?
    public let reasons: [String]
}

public enum PerformanceBudgetGate: Sendable {
    public static func evaluate(
        baseline: PerformanceBenchmarkResult,
        candidate: PerformanceBenchmarkResult,
        budget: PerformanceRegressionBudget
    ) -> PerformanceBudgetEvaluation {
        let differences = incomparableReasons(baseline.workload, candidate.workload)
        guard differences.isEmpty else {
            return PerformanceBudgetEvaluation(
                comparable: false,
                passed: false,
                wallClockRegressionPercent: nil,
                peakMemoryRegressionPercent: nil,
                reasons: differences
            )
        }
        let wallClockRegression = regressionPercent(
            baseline: baseline.wallClockSecondsMedian,
            candidate: candidate.wallClockSecondsMedian
        )
        let wallClockRegressionSeconds = candidate.wallClockSecondsMedian - baseline.wallClockSecondsMedian
        let memoryRegression = regressionPercent(
            baseline: Double(baseline.peakMemoryBytesMedian),
            candidate: Double(candidate.peakMemoryBytesMedian)
        )
        var reasons: [String] = []
        if wallClockRegression > budget.maximumWallClockRegressionPercent,
            wallClockRegressionSeconds > budget.maximumWallClockRegressionSeconds
        {
            if budget.maximumWallClockRegressionSeconds == 0 {
                reasons.append("wall-clock regression exceeds \(budget.maximumWallClockRegressionPercent)%")
            } else {
                reasons.append(
                    "wall-clock regression exceeds \(budget.maximumWallClockRegressionPercent)% and "
                        + "\(budget.maximumWallClockRegressionSeconds) seconds"
                )
            }
        }
        if memoryRegression > budget.maximumPeakMemoryRegressionPercent {
            reasons.append("peak-memory regression exceeds \(budget.maximumPeakMemoryRegressionPercent)%")
        }
        return PerformanceBudgetEvaluation(
            comparable: true,
            passed: reasons.isEmpty,
            wallClockRegressionPercent: wallClockRegression,
            peakMemoryRegressionPercent: memoryRegression,
            reasons: reasons
        )
    }

    private static func incomparableReasons(
        _ baseline: PerformanceWorkloadIdentity,
        _ candidate: PerformanceWorkloadIdentity
    ) -> [String] {
        var reasons: [String] = []
        if baseline.analyzer != candidate.analyzer {
            reasons.append("analyzer differs")
        }
        if baseline.workloadFamily != candidate.workloadFamily {
            reasons.append("workload family differs")
        }
        if baseline.inputSHA256 != candidate.inputSHA256 {
            reasons.append("input checksum differs")
        }
        if baseline.commandFingerprint != candidate.commandFingerprint {
            reasons.append("command fingerprint differs")
        }
        if baseline.analysisMode != candidate.analysisMode {
            reasons.append("analysis mode differs")
        }
        if baseline.optionalContext != candidate.optionalContext {
            reasons.append("optional context differs")
        }
        return reasons
    }

    private static func regressionPercent(baseline: Double, candidate: Double) -> Double {
        guard baseline > 0 else { return candidate > 0 ? .infinity : 0 }
        return ((candidate - baseline) / baseline) * 100
    }
}
