import Foundation
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
            switch try CLIOptions().parse(Array(CommandLine.arguments.dropFirst())) {
            case .help:
                print(CLIOptions.help)
            case .version:
                print("SwiftDebt 0.1.0")
            case .analyze(let request, let interactiveDebt):
                let result = try await AnalysisService().run(request)
                if interactiveDebt, let rankedDebtAnalysis = result.rankedDebtAnalysis {
                    try TerminalDebtExplorer.run(
                        rankedDebtAnalysis,
                        environment: .current(),
                        fallbackOutput: result.standardOutput,
                        dependencies: .live(sourceRoot: interactiveSourceRoot(for: request))
                    )
                } else {
                    FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
                }
                exit(result.exitStatus)
            case .debtValidate(let request, let validation):
                let result = try await AnalysisService().run(request)
                let outcome = DebtValidationOutcome(analysis: result.rankedDebtAnalysis, validation: validation)
                if !validation.quiet {
                    FileHandle.standardOutput.write(Data(outcome.summary.utf8))
                }
                exit(result.exitStatus == 2 ? 2 : outcome.exitStatus)
            case .compare(let request):
                let result = try DebtImprovementService().compare(request)
                FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
                exit(result.exitStatus)
            case .validateImprovement(let request):
                let result = try DebtImprovementService().validateImprovement(request)
                FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
                exit(result.exitStatus)
            case .explainCoverage(let request):
                let result = try CoverageExplanationService().run(request)
                FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
                exit(0)
            case .performanceGate(let request):
                let result = try PerformanceGateCLI.run(request)
                FileHandle.standardOutput.write(Data(result.output.utf8))
                exit(result.exitStatus)
            }
        } catch {
            let message = "swift-debt: error: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
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
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? input : input.deletingLastPathComponent()
    }
}

private struct InteractiveSourceManifest: Decodable {
    let root: String
}
