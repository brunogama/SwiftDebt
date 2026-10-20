import Foundation
import SwiftDebtCore
import SwiftDebtInteractive
import SwiftDebtKit

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@main
struct SwiftDebtCommand {
    static func main() async {
        do {
            try await run(CLIOptions().parse(Array(CommandLine.arguments.dropFirst())))
        } catch {
            let message = "swift-debt: error: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
    }

    private static func run(_ action: CLIAction) async throws {
        switch action {
        case .help:
            write(CLIOptions.help + "\n")
        case .version:
            write("SwiftDebt \(SwiftDebtRelease.version)\n")
        case .analyze(let request, let interactiveDebt):
            try await runAnalysis(request, interactiveDebt: interactiveDebt)
        case .debtValidate(let request, let validation):
            try await runValidation(request, validation: validation)
        case .compare(let request):
            let result = try DebtImprovementService().compare(request)
            write(result.standardOutput)
            exit(result.exitStatus)
        case .validateImprovement(let request):
            let result = try DebtImprovementService().validateImprovement(request)
            write(result.standardOutput)
            exit(result.exitStatus)
        case .explainCoverage(let request):
            let result = try CoverageExplanationService().run(request)
            write(result.standardOutput)
            exit(0)
        case .performanceGate(let request):
            let result = try PerformanceGateCLI.run(request)
            write(result.output)
            exit(result.exitStatus)
        case .pipeline(let request):
            let result = try PipelineCLI.run(request)
            write(result.output)
            exit(result.exitStatus)
        }
    }

    private static func runAnalysis(
        _ request: AnalysisRequest, interactiveDebt: Bool
    ) async throws {
        let result = try await AnalysisService().run(request)
        if interactiveDebt, let ranked = result.rankedDebtAnalysis {
            try TerminalDebtExplorer.run(
                ranked, environment: .current(), fallbackOutput: result.standardOutput,
                dependencies: .live(sourceRoot: interactiveSourceRoot(for: request)))
        } else {
            write(result.standardOutput)
        }
        exit(result.exitStatus)
    }

    private static func runValidation(
        _ request: AnalysisRequest, validation: DebtValidationOptions
    ) async throws {
        let result = try await AnalysisService().run(request)
        let outcome = DebtValidationOutcome(
            analysis: result.rankedDebtAnalysis, validation: validation)
        if !validation.quiet { write(outcome.summary) }
        exit(result.exitStatus == 2 ? 2 : outcome.exitStatus)
    }

    private static func write(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }

    private static func interactiveSourceRoot(for request: AnalysisRequest) -> URL? {
        if let manifestPath = request.manifestPath,
            let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
            let manifest = try? JSONDecoder().decode(InteractiveSourceManifest.self, from: data)
        {
            return URL(fileURLWithPath: manifest.root).standardizedFileURL.resolvingSymlinksInPath()
        }

        let input = URL(fileURLWithPath: request.path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else {
            return nil
        }
        return isDirectory.boolValue ? input : input.deletingLastPathComponent()
    }
}

private struct InteractiveSourceManifest: Decodable {
    let root: String
}
