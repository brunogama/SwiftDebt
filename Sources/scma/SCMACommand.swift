import Foundation
import SCMAInteractive
import SCMAKit

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@main
struct SCMACommand {
    static func main() async {
        do {
            switch try CLIOptions().parse(Array(CommandLine.arguments.dropFirst())) {
            case .help:
                print(CLIOptions.help)
            case .version:
                print("SwiftSCMA 0.1.0")
            case .analyze(let request, let interactiveDebt):
                let result = try await AnalysisService().run(request)
                if interactiveDebt, let rankedDebtAnalysis = result.rankedDebtAnalysis {
                    let explorer = TerminalDebtExplorer.render(
                        rankedDebtAnalysis,
                        environment: .current(),
                        fallbackOutput: result.standardOutput
                    )
                    FileHandle.standardOutput.write(Data(explorer.text.utf8))
                } else {
                    FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
                }
                exit(result.exitStatus)
            case .explainCoverage(let request):
                let result = try CoverageExplanationService().run(request)
                FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
                exit(0)
            }
        } catch {
            let message = "scma: error: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
    }
}
