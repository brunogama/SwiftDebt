import Foundation
import SCMACore
import SCMAInteractive
import Testing

@Suite("Interactive debt explorer")
struct DebtExplorerTests {
    @Test func reducerAppliesPrioritySearchSelectionAndDetailDeterministically() throws {
        let analysis = rankedAnalysis(count: 4)
        let actions: [DebtExplorerAction] = [
            .setPriorityFilter(.high),
            .moveSelection(1),
            .setSearchQuery("worker 2"),
            .selectVisibleItem(offset: 0),
        ]

        let first = actions.reduce(DebtExplorerState(analysis: analysis)) { state, action in
            DebtExplorerReducer.reduce(state, action)
        }
        let second = actions.reduce(DebtExplorerState(analysis: analysis)) { state, action in
            DebtExplorerReducer.reduce(state, action)
        }
        let detail = try #require(first.selectedDetail(editor: "vim"))

        #expect(first == second)
        #expect(first.visibleItemIDs == ["callable:Worker2.run"])
        #expect(first.selectedItemID == "callable:Worker2.run")
        #expect(detail.sourceContext.contains("Sources/Worker2.swift:12:3"))
        #expect(detail.sourceContext.contains("Evidence:"))
        #expect(detail.scoreExplanation.contains("swift.cognitive-complexity"))
        #expect(detail.editorCommand == "vim +12 Sources/Worker2.swift")
    }

    @Test func terminalCapabilityDetectionFallsBackWhenInteractiveOutputIsUnsafe() {
        let analysis = rankedAnalysis(count: 2)
        let ci = TerminalEnvironment(
            standardInputIsTTY: true,
            standardOutputIsTTY: true,
            term: "xterm-256color",
            ci: "true"
        )
        let dumb = TerminalEnvironment(
            standardInputIsTTY: true,
            standardOutputIsTTY: true,
            term: "dumb",
            ci: nil
        )
        let capable = TerminalEnvironment(
            standardInputIsTTY: true,
            standardOutputIsTTY: true,
            term: "xterm-256color",
            ci: nil
        )

        let ciOutput = TerminalDebtExplorer.render(analysis, environment: ci, fallbackOutput: "fallback\n")
        let dumbOutput = TerminalDebtExplorer.render(analysis, environment: dumb, fallbackOutput: "fallback\n")
        let interactiveOutput = TerminalDebtExplorer.render(analysis, environment: capable, fallbackOutput: "fallback\n")

        #expect(ciOutput.usedFallback)
        #expect(ciOutput.text == "fallback\n")
        #expect(dumbOutput.usedFallback)
        #expect(dumbOutput.reason == "TERM=dumb")
        #expect(!interactiveOutput.usedFallback)
        #expect(interactiveOutput.text.contains("SwiftSCMA debt explorer"))
        #expect(interactiveOutput.text.contains("Commands:"))
    }

    @Test func commandFallsBackToDebtReportWhenInteractiveDebtRunsWithoutTTY() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "final class Worker { func run(_ value: Int) { if value > 0 { print(value) } } }\n".write(
            to: directory.appendingPathComponent("Worker.swift"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runSCMA(
            arguments: ["analyze", directory.path, "--interactive-debt", "--format", "debt-compact"]
        )

        #expect(result.status == 0)
        #expect(result.stderr == "")
        #expect(result.stdout.contains("callable:Workspace.Worker.run"))
        #expect(!result.stdout.contains("SwiftSCMA debt explorer"))
        #expect(!result.stdout.contains("Commands:"))
    }

    @Test func largeResultSetsStayWithinReducerPerformanceBudget() {
        let analysis = rankedAnalysis(count: 12_000)
        let clock = ContinuousClock()
        let start = clock.now
        var state = DebtExplorerState(analysis: analysis)
        state = DebtExplorerReducer.reduce(state, .setSearchQuery("worker"))
        for _ in 0..<4_000 {
            state = DebtExplorerReducer.reduce(state, .moveSelection(1))
        }
        let elapsed = start.duration(to: clock.now)

        #expect(state.visibleItemIDs.count == 12_000)
        #expect(elapsed < .milliseconds(750))
    }

    private func runSCMA(arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = try scmaExecutableURL()
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "CI": "false",
            "TERM": "xterm-256color",
        ]) { _, new in new }
        process.standardInput = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stdoutText, stderrText)
    }

    private func scmaExecutableURL() throws -> URL {
        let buildDirectory = repositoryRoot.appendingPathComponent(".build")
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: buildDirectory, includingPropertiesForKeys: nil) else {
            throw TestSupportError.missingExecutable
        }
        let candidates = enumerator.compactMap { entry -> URL? in
            guard let url = entry as? URL, url.lastPathComponent == "scma",
                manager.isExecutableFile(atPath: url.path)
            else { return nil }
            return url
        }
        guard let executable = candidates.sorted(by: { $0.path < $1.path }).first else {
            throw TestSupportError.missingExecutable
        }
        return executable
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private enum TestSupportError: Error {
        case missingExecutable
    }

    private func rankedAnalysis(count: Int) -> RankedDebtAnalysis {
        let items = (0..<count).map { index in
            rankedItem(
                id: "callable:Worker\(index).run",
                name: "Worker \(index) run",
                priority: index.isMultiple(of: 2) ? .high : .medium,
                score: index.isMultiple(of: 2) ? 80 : 55,
                file: "Sources/Worker\(index).swift",
                line: 10 + index
            )
        }
        return RankedDebtAnalysis(
            options: DebtAnalysisOptions(aggregationStrategy: .none),
            items: items,
            aggregations: [],
            compactItems: [],
            summary: DebtAnalysisSummary(
                totalItemCount: count,
                rankedItemCount: count,
                aggregationCount: 0,
                unavailableEvidenceCount: 0,
                priorityCounts: ["high": (count + 1) / 2, "medium": count / 2]
            )
        )
    }

    private func rankedItem(
        id: String,
        name: String,
        priority: Priority,
        score: Double,
        file: String,
        line: Int
    ) -> RankedDebtItem {
        let location = DebtLocation(module: "Workspace", file: file, line: line, column: 3)
        let evidence = DebtEvidence(
            id: "\(id):complexity",
            kind: "swift.cognitive-complexity",
            weight: 1,
            normalizedScore: score,
            rawValue: "cognitive=\(Int(score / 5))",
            location: location,
            note: "measured"
        )
        return RankedDebtItem(
            item: DebtItem(
                id: id,
                entity: DebtEntity(id: id, displayName: name, level: .callable, location: location),
                evidence: [evidence]
            ),
            score: DebtScore(
                value: score,
                priority: priority,
                breakdown: DebtScoreBreakdown(
                    totalConfiguredWeight: 1,
                    totalAvailableWeight: 1,
                    contributions: [
                        DebtScoreContribution(
                            evidenceID: evidence.id,
                            kind: evidence.kind,
                            rawValue: evidence.rawValue,
                            normalizedScore: score,
                            configuredWeight: 1,
                            effectiveWeight: 1,
                            contribution: score,
                            note: evidence.note
                        )
                    ],
                    unavailableEvidence: []
                )
            ),
            category: "swift",
            explanation: "Complexity concentrates change risk.",
            recommendation: "Extract smaller operations."
        )
    }
}
