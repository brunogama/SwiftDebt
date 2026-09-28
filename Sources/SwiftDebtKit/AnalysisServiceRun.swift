import Foundation
import SwiftDebtCore
import SwiftDebtReporting

extension AnalysisService {
    public func run(_ request: AnalysisRequest) async throws -> AnalysisRunResult {
        let profiler = request.profileOutputPath == nil ? nil : AnalysisProfiler()
        let workspace = try prepare(request, profiler: profiler)
        let report = try await Analyzer().analyze(
            workspace.sources, options: workspace.options,
            jobs: request.jobs ?? workspace.configuration.jobs, phaseSink: profiler
        )
        let rankedDebtAnalysis = rankedDebtAnalysis(
            for: report, request: request, workspace: workspace, profiler: profiler)
        let format = request.format ?? workspace.configuration.format
        let debtValidationDiagnostics = debtValidationDiagnostics(
            workspace.configuration.debtValidation,
            analysis: rankedDebtAnalysis,
            root: workspace.root
        )
        let rendered = try render(
            ReportRenderingInput(
                report: report, rankedDebtAnalysis: rankedDebtAnalysis, format: format,
                root: workspace.root, diagnostics: debtValidationDiagnostics, profiler: profiler))
        var protectedPaths = protectedPaths(for: request, workspace: workspace)
        try writeReport(rendered, request: request, protectedPaths: &protectedPaths)
        let profile = profiler?.profile()
        try writeProfile(profile, request: request, protectedPaths: &protectedPaths)
        let status = exitStatus(
            report: report, rankedDebtAnalysis: rankedDebtAnalysis,
            validation: workspace.configuration.debtValidation,
            failOnViolation: request.failOnViolation || workspace.configuration.failOnViolation)
        try writeStamp(request.stampPath, status: status, protectedPaths: protectedPaths)
        return AnalysisRunResult(
            report: report,
            standardOutput: request.outputPath == nil ? rendered : "",
            exitStatus: status,
            rankedDebtAnalysis: rankedDebtAnalysis,
            profile: profile
        )
    }
}
