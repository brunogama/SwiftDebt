import Foundation
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
            case .analyze(let request):
                let result = try await AnalysisService().run(request)
                FileHandle.standardOutput.write(Data(result.standardOutput.utf8))
                exit(result.exitStatus)
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
            }
        } catch {
            let message = "scma: error: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(2)
        }
    }
}
