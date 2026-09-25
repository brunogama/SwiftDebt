import Foundation
import SwiftDebtCore
import Testing

@Suite("Peak-memory performance gate CLI")
struct PerformanceMemoryHeadroomCLIWorkflowTests {
    @Test("The real CLI accepts the PR 62 artifact and rejects a two MiB plus one regression")
    func exactArtifactAndNegativeCase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDebtMemoryHeadroom-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baselineURL = directory.appendingPathComponent("baseline.json")
        let candidateURL = directory.appendingPathComponent("candidate.json")
        let outputURL = directory.appendingPathComponent("evaluation.json")
        let baselineMemory: UInt64 = 10_706_944

        try write(
            benchmark(wallClock: 0.027_048_042, memory: baselineMemory),
            to: baselineURL
        )
        try write(
            benchmark(wallClock: 0.028_160_812_5, memory: 12_484_608),
            to: candidateURL
        )

        let passing = try runSwiftDebt(
            arguments(
                baseline: baselineURL,
                candidate: candidateURL,
                output: outputURL
            ))
        let passingEvaluation = try decode(outputURL)

        #expect(passing.status == 0)
        #expect(passing.stdout.isEmpty)
        #expect(passing.stderr.isEmpty)
        #expect(passingEvaluation.passed)
        #expect(passingEvaluation.peakMemoryRegressionBytes == 1_777_664)

        try write(
            benchmark(wallClock: 0.028_160_812_5, memory: baselineMemory + 2_097_153),
            to: candidateURL
        )
        let failing = try runSwiftDebt(
            arguments(
                baseline: baselineURL,
                candidate: candidateURL,
                output: outputURL
            ))
        let failingEvaluation = try decode(outputURL)

        #expect(failing.status == 1)
        #expect(failing.stdout.isEmpty)
        #expect(failing.stderr.isEmpty)
        #expect(!failingEvaluation.passed)
        #expect(failingEvaluation.peakMemoryRegressionBytes == 2_097_153)
        #expect(
            failingEvaluation.reasons == [
                "peak-memory regression exceeds 15.0% and 2097152 bytes (observed 2097153 bytes)"
            ]
        )
    }

    @Test(arguments: ["-1", "1.5", "18446744073709551616"])
    func invalidAbsoluteMemoryLimitFailsClosed(_ value: String) throws {
        let result = try runSwiftDebt([
            "performance-gate",
            "baseline.json",
            "candidate.json",
            "--max-wall-clock-regression", "10",
            "--max-peak-memory-regression", "15",
            "--max-peak-memory-regression-bytes", value,
        ])

        #expect(result.status == 2)
        #expect(result.stdout.isEmpty)
        #expect(
            result.stderr
                == "swift-debt: error: --max-peak-memory-regression-bytes must be a nonnegative integer number of bytes\n"
        )
    }

    private func arguments(
        baseline: URL,
        candidate: URL,
        output: URL
    ) -> [String] {
        [
            "performance-gate",
            baseline.path,
            candidate.path,
            "--name", "baseline-analysis",
            "--max-wall-clock-regression", "10",
            "--max-wall-clock-regression-seconds", "0.010",
            "--max-peak-memory-regression", "15",
            "--max-peak-memory-regression-bytes", "2097152",
            "--output", output.path,
        ]
    }

    private func benchmark(
        wallClock: Double,
        memory: UInt64
    ) -> PerformanceBenchmarkResult {
        PerformanceBenchmarkResult(
            workload: PerformanceWorkloadIdentity(
                analyzer: "SwiftDebt",
                workloadFamily: "SwiftDebt",
                inputSHA256: "f66291244618b5937427f3652bba4fb328c2e9620eab0980a7fcaa378591eb64",
                commandFingerprint: "swift-debt analyze frozen-examples --format json --jobs 1",
                analysisMode: "baseline",
                optionalContext: "none"
            ),
            wallClockSecondsMedian: wallClock,
            peakMemoryBytesMedian: memory,
            pairGenerationID: "b867ee2b6d1e4554aa648aaa453a9db5"
        )
    }

    private func write(
        _ result: PerformanceBenchmarkResult,
        to url: URL
    ) throws {
        try JSONEncoder().encode(result).write(to: url, options: .atomic)
    }

    private func decode(_ url: URL) throws -> PerformanceBudgetEvaluation {
        try JSONDecoder().decode(
            PerformanceBudgetEvaluation.self,
            from: Data(contentsOf: url)
        )
    }
}
