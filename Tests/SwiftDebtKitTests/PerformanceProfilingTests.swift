import Foundation
import SwiftDebtCore
import SwiftDebtKit
import Testing

@Suite("Performance profiling and budgets")
struct PerformanceProfilingTests {
    @Test func profilingWritesMachineReadablePhaseOutputWhenEnabled() async throws {
        let workspace = try makeWorkspace()
        let reportPath = workspace.appendingPathComponent("report.json").path
        let profilePath = workspace.appendingPathComponent("profile.json").path

        let result = try await AnalysisService().run(
            AnalysisRequest(
                path: workspace.path,
                outputPath: reportPath,
                format: .debtJSON,
                enableDebtAnalysis: true,
                lcovPath: "missing.info",
                debtReferenceTime: Date(timeIntervalSince1970: 0),
                profileOutputPath: profilePath
            )
        )

        let profile = try #require(result.profile)
        let data = try Data(contentsOf: URL(fileURLWithPath: profilePath))
        let decoded = try JSONDecoder().decode(AnalysisProfile.self, from: data)
        let phases = Set(decoded.phases.map(\.phase))

        #expect(profile.schemaVersion == 1)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.measurements == ["wall-clock-nanoseconds", "peak-resident-memory-bytes"])
        #expect(decoded.disabledOverhead.clockReads == 0)
        #expect(decoded.disabledOverhead.peakMemoryReads == 0)
        #expect(decoded.disabledOverhead.perSourceWork == 0)
        #expect(
            decoded.disabledOverhead.phaseBoundaryChecks
                == AnalysisProfile.disabledInstrumentationOverhead.phaseBoundaryChecks)
        #expect(phases.isSuperset(of: [.discovery, .parsing, .structuralEvidence, .graph, .coverage]))
        #expect(phases.isSuperset(of: [.repositoryHistory, .functionalEvidence, .scoring, .aggregation, .rendering]))
        #expect(decoded.phases.allSatisfy { $0.elapsedNanoseconds > 0 })
    }

    @Test func profilingIsAbsentByDefaultAndDisabledOverheadIsQuantified() async throws {
        let workspace = try makeWorkspace()

        let result = try await AnalysisService().run(
            AnalysisRequest(path: workspace.path, format: .json)
        )

        #expect(result.profile == nil)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.clockReads == 0)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.peakMemoryReads == 0)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.perSourceWork == 0)
        #expect(AnalysisProfile.disabledInstrumentationOverhead.phaseBoundaryChecks >= AnalysisPhase.allCases.count * 2)
    }

    @Test func performanceGateRejectsIncomparableDebtmapRustWorkloads() {
        let baseline = PerformanceBenchmarkResult(
            workload: PerformanceWorkloadIdentity(
                analyzer: "SwiftDebt",
                workloadFamily: "SwiftDebt",
                inputSHA256: "swift-input",
                commandFingerprint: "swift-debt analyze Examples/Sources --jobs 1",
                analysisMode: "baseline",
                optionalContext: "none"
            ),
            wallClockSecondsMedian: 1,
            peakMemoryBytesMedian: 100
        )
        let candidate = PerformanceBenchmarkResult(
            workload: PerformanceWorkloadIdentity(
                analyzer: "Debtmap",
                workloadFamily: "Debtmap Rust",
                inputSHA256: "rust-input",
                commandFingerprint: "debtmap analyze crates",
                analysisMode: "baseline",
                optionalContext: "none"
            ),
            wallClockSecondsMedian: 1,
            peakMemoryBytesMedian: 100
        )

        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline,
            candidate: candidate,
            budget: PerformanceRegressionBudget(
                name: "baseline-analysis",
                maximumWallClockRegressionPercent: 10,
                maximumPeakMemoryRegressionPercent: 15
            )
        )

        #expect(!evaluation.comparable)
        #expect(!evaluation.passed)
        #expect(evaluation.wallClockRegressionPercent == nil)
        #expect(evaluation.peakMemoryRegressionPercent == nil)
        #expect(evaluation.reasons.contains("analyzer differs"))
        #expect(evaluation.reasons.contains("workload family differs"))
    }

    @Test func performanceGateAppliesWallClockAndMemoryBudgetsForEquivalentWorkloads() {
        let workload = PerformanceWorkloadIdentity(
            analyzer: "SwiftDebt",
            workloadFamily: "SwiftDebt",
            inputSHA256: "swift-input",
            commandFingerprint: "swift-debt analyze Examples/Sources --jobs 1",
            analysisMode: "baseline",
            optionalContext: "none"
        )
        let baseline = PerformanceBenchmarkResult(
            workload: workload,
            wallClockSecondsMedian: 10,
            peakMemoryBytesMedian: 1_000
        )
        let candidate = PerformanceBenchmarkResult(
            workload: workload,
            wallClockSecondsMedian: 11.5,
            peakMemoryBytesMedian: 1_200
        )

        let evaluation = PerformanceBudgetGate.evaluate(
            baseline: baseline,
            candidate: candidate,
            budget: PerformanceRegressionBudget(
                name: "baseline-analysis",
                maximumWallClockRegressionPercent: 10,
                maximumPeakMemoryRegressionPercent: 15
            )
        )

        #expect(evaluation.comparable)
        #expect(!evaluation.passed)
        #expect(evaluation.wallClockRegressionPercent == 15)
        #expect(evaluation.peakMemoryRegressionPercent == 20)
        #expect(evaluation.reasons.contains("wall-clock regression exceeds 10.0%"))
        #expect(evaluation.reasons.contains("peak-memory regression exceeds 15.0%"))
    }

    @Test func performanceGateCLIRejectsMeasuredRegression() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDebtPerformanceGate-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = directory.appendingPathComponent("baseline.json")
        let candidate = directory.appendingPathComponent("candidate.json")
        let output = directory.appendingPathComponent("evaluation.json")
        let workload = PerformanceWorkloadIdentity(
            analyzer: "SwiftDebt",
            workloadFamily: "SwiftDebt",
            inputSHA256: "frozen-input",
            commandFingerprint: "swift-debt debt analyze Examples/Sources --jobs 1",
            analysisMode: "full-evidence",
            optionalContext: "coverage-and-repository-history"
        )
        try write(
            PerformanceBenchmarkResult(
                workload: workload,
                wallClockSecondsMedian: 10,
                peakMemoryBytesMedian: 1_000
            ),
            to: baseline
        )
        try write(
            PerformanceBenchmarkResult(
                workload: workload,
                wallClockSecondsMedian: 13,
                peakMemoryBytesMedian: 1_200
            ),
            to: candidate
        )

        let result = try runSwiftDebt(arguments: [
            "performance-gate",
            baseline.path,
            candidate.path,
            "--name", "full-evidence-analysis",
            "--max-wall-clock-regression", "20",
            "--max-peak-memory-regression", "15",
            "--output", output.path,
        ])
        let evaluation = try JSONDecoder().decode(
            PerformanceBudgetEvaluation.self,
            from: Data(contentsOf: output)
        )

        #expect(result.status == 1)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.isEmpty)
        #expect(evaluation.comparable)
        #expect(!evaluation.passed)
        #expect(evaluation.wallClockRegressionPercent == 30)
        #expect(evaluation.peakMemoryRegressionPercent == 20)
    }

    @Test func benchmarkHarnessRecordsRawSamplesAndMachineReadableMedian() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDebtBenchmarkHarness-")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("input.swift")
        let output = directory.appendingPathComponent("result.json")
        try "struct Input {}\n".write(to: input, atomically: true, encoding: .utf8)
        let root = repositoryRoot
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [
            root.appendingPathComponent("scripts/run_debtmap_benchmark.py").path,
            "--output", output.path,
            "--input", input.path,
            "--analyzer", "SwiftDebt",
            "--workload-family", "SwiftDebt",
            "--command-fingerprint", "true",
            "--analysis-mode", "baseline",
            "--optional-context", "none",
            "--warmups", "0",
            "--runs", "2",
            "--",
            "/usr/bin/true",
        ]
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        #expect(process.terminationStatus == 0, Comment(rawValue: errorText))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any]
        )
        let samples = try #require(object["samples"] as? [[String: Any]])
        #expect(samples.count == 2)
        #expect((object["wallClockSecondsMedian"] as? Double) ?? 0 > 0)
        #expect((object["wallClockSecondsMinimum"] as? Double) ?? 0 > 0)
        #expect((object["wallClockSecondsMaximum"] as? Double) ?? 0 > 0)
        #expect((object["peakMemoryBytesMedian"] as? Int) ?? 0 > 0)
        #expect((object["peakMemoryBytesMinimum"] as? Int) ?? 0 > 0)
        #expect((object["peakMemoryBytesMaximum"] as? Int) ?? 0 > 0)
        let metadata = try #require(object["metadata"] as? [String: Any])
        #expect(!((metadata["swiftVersion"] as? String) ?? "").isEmpty)
        #expect(!((metadata["os"] as? String) ?? "").isEmpty)
        #expect(!((metadata["cpuModel"] as? String) ?? "").isEmpty)
        #expect((metadata["memoryBytes"] as? Int) ?? 0 > 0)
        let decoded = try JSONDecoder().decode(PerformanceBenchmarkResult.self, from: Data(contentsOf: output))
        #expect(decoded.workload.inputSHA256.count == 64)
        #expect(decoded.workload.analysisMode == "baseline")
    }

    private func makeWorkspace() throws -> URL {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftDebtPerformanceProfiling-")
            .appendingPathComponent(UUID().uuidString)
        let sourceDirectory = workspace.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try """
        final class ProfiledExample {
            let value = 1

            func answer(_ input: Int) -> Int {
                if input > value {
                    return input
                }
                return value
            }
        }
        """.write(
            to: sourceDirectory.appendingPathComponent("Example.swift"),
            atomically: true,
            encoding: .utf8
        )
        return workspace
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func runSwiftDebt(arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = try swiftDebtExecutableURL()
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private func swiftDebtExecutableURL() throws -> URL {
        let buildDirectory = repositoryRoot.appendingPathComponent(".build")
        let manager = FileManager.default
        let enumerator = try #require(manager.enumerator(at: buildDirectory, includingPropertiesForKeys: nil))
        let candidates = enumerator.compactMap { entry -> URL? in
            guard let url = entry as? URL, url.lastPathComponent == "swift-debt",
                manager.isExecutableFile(atPath: url.path)
            else { return nil }
            return url
        }
        return try #require(candidates.sorted { $0.path < $1.path }.first)
    }
}
