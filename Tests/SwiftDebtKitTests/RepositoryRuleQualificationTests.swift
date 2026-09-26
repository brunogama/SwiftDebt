import Foundation
import Testing

@Suite("R2 repository rule qualification", .serialized)
struct RepositoryRuleQualificationTests {
    @Test("Corpus schema and renderer invariants")
    func corpusInvariants() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3",
            "-m",
            "unittest",
            "scripts/tests/test_repository_qualification.py",
        ]
        process.currentDirectoryURL = repositoryRoot
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        #expect(process.terminationStatus == 0, Comment(rawValue: diagnostic))
    }

    @Test("Frozen corpus runs through the real CLI with reproducible evidence")
    func frozenCorpus() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swiftdebt-qualification-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = temporary.appendingPathComponent("qualification.json")
        let fixture = repositoryRoot.appendingPathComponent(
            "Tests/SwiftDebtKitTests/Fixtures/RepositoryQualification/qualification-report.golden.json"
        )
        var arguments = [
            "python3",
            repositoryRoot.appendingPathComponent("scripts/evaluate_repository_qualification.py").path,
            "--swift-debt", try swiftDebtExecutableURL().path,
            "--output", output.path,
        ]
        #if os(macOS)
            arguments += [
                "--expect", fixture.path,
                "--determinism-runs", "10",
                "--parse-jobs", "1,2,8",
                "--verify-network-denied",
            ]
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryRoot
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(
            decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )

        #expect(process.terminationStatus == 0, Comment(rawValue: diagnostic))
        let report = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any]
        )
        #expect(report["qualificationState"] as? String == "blocked-pending-independent-review")
        let gate = try #require(report["gate"] as? [String: Any])
        #expect(gate["syntheticEngineeringEvidence"] as? String == "pass")
        #expect(gate["releaseQualification"] as? String == "blocked")
        let rules = try #require(report["rules"] as? [[String: Any]])
        #expect(rules.count == 2)
        for rule in rules {
            let identity = try #require(rule["ruleIdentity"] as? String)
            let counts = try #require(rule["authoredCaseCounts"] as? [String: Any])
            #expect(counts["positive"] as? Int == 30)
            #expect(counts["adversarialNegative"] as? Int == 60)
            #expect(
                counts["outOfScope"] as? Int
                    == (identity == "swiftdebt.refactoring.repeated-switches" ? 30 : 0)
            )
            #expect(counts["repositoryShapes"] as? Int == 3)
            #expect(rule["supportState"] as? String == "Research")
            #expect(
                rule["provisionalMetricsPopulation"] as? String
                    == "positive-and-adversarial-negative-cases-only"
            )
            let matrix = try #require(rule["provisionalConfusionMatrix"] as? [String: Any])
            #expect(matrix["truePositive"] as? Int == 30)
            #expect(matrix["trueNegative"] as? Int == 60)
            #expect(matrix["falsePositive"] as? Int == 0)
            #expect(matrix["falseNegative"] as? Int == 0)
            let outOfScopeIDs = try #require(rule["outOfScopeCaseIDs"] as? [String])
            #expect(
                outOfScopeIDs.count
                    == (identity == "swiftdebt.refactoring.repeated-switches" ? 30 : 0)
            )
        }
        let snapshots = try #require(report["realWorldSnapshots"] as? [[String: Any]])
        #expect(snapshots.count == 2)
        for snapshot in snapshots {
            let notes = try #require(snapshot["provisionalAuditNotes"] as? [String])
            #expect(!notes.isEmpty)
            #expect(snapshot["metricsInclusion"] as? String == "excluded-until-independent-case-labeling")
        }
        #if os(macOS)
            let determinism = try #require(report["determinism"] as? [String: Any])
            #expect(determinism["totalRuns"] as? Int == 30)
            #expect(determinism["allRunsByteIdentical"] as? Bool == true)
            let network = try #require(report["networkIsolation"] as? [String: Any])
            #expect(network["status"] as? String == "pass")
        #endif
    }
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
