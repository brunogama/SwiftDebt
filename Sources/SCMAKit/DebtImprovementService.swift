import Foundation
import SCMACore

public struct DebtComparisonRequest: Sendable {
    public let beforePath: String
    public let afterPath: String
    public let outputPath: String?

    public init(beforePath: String, afterPath: String, outputPath: String? = nil) {
        self.beforePath = beforePath
        self.afterPath = afterPath
        self.outputPath = outputPath
    }
}

public struct DebtValidationRequest: Sendable {
    public let beforePath: String
    public let afterPath: String
    public let minimumImprovement: Double
    public let outputPath: String?

    public init(beforePath: String, afterPath: String, minimumImprovement: Double = 0, outputPath: String? = nil) {
        self.beforePath = beforePath
        self.afterPath = afterPath
        self.minimumImprovement = minimumImprovement
        self.outputPath = outputPath
    }
}

public struct DebtWorkflowRunResult: Sendable {
    public let standardOutput: String
    public let exitStatus: Int32

    public init(standardOutput: String, exitStatus: Int32) {
        self.standardOutput = standardOutput
        self.exitStatus = exitStatus
    }
}

public struct DebtImprovementService: Sendable {
    public init() {}

    public func compare(_ request: DebtComparisonRequest) throws -> DebtWorkflowRunResult {
        let comparison = try loadComparison(beforePath: request.beforePath, afterPath: request.afterPath)
        let rendered = try renderJSON(comparison)
        try writeIfRequested(rendered, outputPath: request.outputPath, protectedPaths: [request.beforePath, request.afterPath])
        return DebtWorkflowRunResult(standardOutput: request.outputPath == nil ? rendered : "", exitStatus: 0)
    }

    public func validateImprovement(_ request: DebtValidationRequest) throws -> DebtWorkflowRunResult {
        guard request.minimumImprovement >= 0 else {
            throw AnalysisFailure.invalidConfiguration("minimum improvement must be nonnegative")
        }
        let comparison = try loadComparison(beforePath: request.beforePath, afterPath: request.afterPath)
        let observedImprovement = comparison.summary.beforeTotalScore - comparison.summary.afterTotalScore
        let passed = observedImprovement >= request.minimumImprovement
        let status: Int32 = passed ? 0 : 1
        let validation = DebtImprovementValidation(
            threshold: request.minimumImprovement,
            observedImprovement: observedImprovement,
            passed: passed,
            exitStatus: status,
            comparisonSummary: comparison.summary
        )
        let rendered = try renderJSON(validation)
        try writeIfRequested(rendered, outputPath: request.outputPath, protectedPaths: [request.beforePath, request.afterPath])
        return DebtWorkflowRunResult(standardOutput: request.outputPath == nil ? rendered : "", exitStatus: status)
    }

    private func loadComparison(beforePath: String, afterPath: String) throws -> DebtReportComparison {
        let before: DebtReport = try loadDebtReport(path: beforePath, label: "before")
        let after: DebtReport = try loadDebtReport(path: afterPath, label: "after")
        return try DebtReportComparator().compare(before: before, after: after)
    }

    private func loadDebtReport(path: String, label: String) throws -> DebtReport {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try JSONDecoder().decode(DebtReport.self, from: data)
        } catch let failure as AnalysisFailure {
            throw failure
        } catch let failure as DecodingError {
            throw AnalysisFailure.invalidConfiguration("Invalid \(label) debt report \(path): \(decodingErrorDescription(failure))")
        } catch {
            throw WorkspaceError("Unable to read \(label) debt report \(path): \(error)")
        }
    }

    private func renderJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self) + "\n"
    }

    private func writeIfRequested(_ content: String, outputPath: String?, protectedPaths: [String]) throws {
        guard let outputPath else { return }
        let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL.resolvingSymlinksInPath()
        let protected = Set(protectedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path })
        guard !protected.contains(outputURL.path), outputURL.pathExtension != "swift" else {
            throw WorkspaceError("Refusing to overwrite an input report or Swift file")
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
    }

}
