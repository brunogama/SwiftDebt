import Foundation
import SwiftDebtCore
import SwiftDebtKit
import Testing

@Suite("R2 repository evidence CLI integration")
struct RepositoryAnalysisCLIWorkflowTests {
    @Test("Real CLI text and sidecar match reviewed goldens and remain deterministic")
    func goldenCLIOutput() throws {
        let first = try makeFixtureCopy()
        let second = try makeFixtureCopy()
        defer {
            try? FileManager.default.removeItem(at: first.root)
            try? FileManager.default.removeItem(at: second.root)
        }

        let firstRun = try runSwiftDebt([
            "analyze", first.input.path, "--jobs", "1", "--repository-evidence", first.sidecar.path,
        ])
        let secondRun = try runSwiftDebt([
            "analyze", second.input.path, "--jobs", "4", "--repository-evidence", second.sidecar.path,
        ])
        let gated = try runSwiftDebt([
            "analyze", first.input.path, "--jobs", "1", "--repository-evidence", first.gatedSidecar.path,
            "--fail-on-violation",
        ])
        let firstJSON = try String(contentsOf: first.sidecar, encoding: .utf8)
        let secondJSON = try String(contentsOf: second.sidecar, encoding: .utf8)
        let expectedJSON = try fixtureText("repository-evidence.golden.json")
        let expectedText = try fixtureText("repository-evidence.golden.txt")

        #expect(firstRun.status == 0)
        #expect(secondRun.status == 0)
        #expect(gated.status == 0, "Research-qualified repository rules remain advisory")
        #expect(firstRun.stderr.isEmpty)
        #expect(secondRun.stderr.isEmpty)
        #expect(firstJSON == secondJSON)
        let actualReport = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: Data(firstJSON.utf8))
        #expect(actualReport.generator == "SwiftDebt \(SwiftDebtRelease.version)")
        #expect(try normalizingRepositoryGenerator(firstJSON) == normalizingRepositoryGenerator(expectedJSON))
        #expect(repositorySection(firstRun.stdout) == expectedText)
        #expect(repositorySection(secondRun.stdout) == expectedText)
    }

    @Test("Schema 2 JSON remains separate from the repository evidence sidecar")
    func schemaTwoIsolation() throws {
        let fixture = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runSwiftDebt([
            "analyze", fixture.input.path, "--jobs", "1", "--format", "json",
            "--repository-evidence", fixture.sidecar.path,
        ])
        let analysis = try JSONDecoder().decode(AnalysisReport.self, from: Data(result.stdout.utf8))
        let repository = try JSONDecoder().decode(
            RepositoryEvidenceReport.self,
            from: Data(contentsOf: fixture.sidecar)
        )

        #expect(result.status == 0)
        #expect(analysis.schemaVersion == 2)
        #expect(repository.schemaVersion == 1)
        #expect(repository.reportKind == "swiftdebt-repository-evidence")
        #expect(!result.stdout.contains("swiftdebt-repository-evidence"))
        #expect(!result.stdout.contains("data-clumps"))
    }

    @Test("Repeated CLI runs exclude their sidecar from Git provenance")
    func repeatedCLIRunsKeepGitProvenanceStable() throws {
        let fixture = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try runGitFixture(["init"], root: fixture.root)
        try runGitFixture(["config", "user.name", "Test User"], root: fixture.root)
        try runGitFixture(["config", "user.email", "test@example.test"], root: fixture.root)
        try runGitFixture(["add", "input"], root: fixture.root)
        try runGitFixture(["commit", "-m", "fixture"], root: fixture.root)
        let nestedSidecar = fixture.root.appendingPathComponent(".swift-debt/repository-evidence.json")

        let first = try runSwiftDebt([
            "analyze", fixture.root.path, "--jobs", "1", "--repository-evidence", nestedSidecar.path,
        ])
        let firstBytes = try Data(contentsOf: nestedSidecar)
        let firstReport = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: firstBytes)
        let second = try runSwiftDebt([
            "analyze", fixture.root.path, "--jobs", "1", "--repository-evidence", nestedSidecar.path,
        ])
        let secondBytes = try Data(contentsOf: nestedSidecar)
        let secondReport = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: secondBytes)

        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(firstReport.snapshot.versionControl?.workingTreeState == .clean)
        #expect(secondReport.snapshot.versionControl?.workingTreeState == .clean)
        #expect(firstBytes == secondBytes)
    }

    @Test("Lifecycle and repository outputs are both excluded from Git provenance")
    func combinedLifecycleAndRepositoryOutputsKeepGitProvenanceStable() throws {
        let fixture = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try runGitFixture(["init"], root: fixture.root)
        try runGitFixture(["config", "user.name", "Test User"], root: fixture.root)
        try runGitFixture(["config", "user.email", "test@example.test"], root: fixture.root)
        try runGitFixture(["add", "input"], root: fixture.root)
        try runGitFixture(["commit", "-m", "fixture"], root: fixture.root)
        let lifecycle = fixture.root.appendingPathComponent(".swift-debt/lifecycle.json")
        let sidecar = fixture.root.appendingPathComponent(".swift-debt/repository-evidence.json")
        let arguments = [
            "analyze", fixture.root.path, "--jobs", "1",
            "--lifecycle-artifact", lifecycle.path,
            "--repository-evidence", sidecar.path,
        ]

        let first = try runSwiftDebt(arguments)
        let firstBytes = try Data(contentsOf: sidecar)
        let firstReport = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: firstBytes)
        let second = try runSwiftDebt(arguments)
        let secondBytes = try Data(contentsOf: sidecar)
        let secondReport = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: secondBytes)

        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(firstReport.snapshot.versionControl?.workingTreeState == .clean)
        #expect(secondReport.snapshot.versionControl?.workingTreeState == .clean)
        #expect(firstBytes == secondBytes)
    }

    @Test("Incomplete repository evidence exits two and never claims absence")
    func incompleteCLIOutcome() throws {
        let fixture = try makeFixtureCopy(named: "Conditional")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runSwiftDebt([
            "analyze", fixture.input.path, "--jobs", "1", "--repository-evidence", fixture.sidecar.path,
        ])
        let report = try JSONDecoder().decode(
            RepositoryEvidenceReport.self,
            from: Data(contentsOf: fixture.sidecar)
        )

        #expect(result.status == 2)
        #expect(!report.isComplete)
        #expect(result.stdout.contains("Status: INCOMPLETE"))
        #expect(result.stdout.contains("Absence was not established"))
    }

    @Test("Repository evidence cannot overwrite another requested output")
    func rejectsOutputCollisionBeforeWriting() throws {
        let fixture = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let collision = fixture.root.appendingPathComponent("collision.json")

        let result = try runSwiftDebt([
            "analyze", fixture.input.path, "--format", "json", "--output", collision.path,
            "--repository-evidence", collision.path,
        ])

        #expect(result.status == 2)
        #expect(result.stderr.contains("another output"))
        #expect(!FileManager.default.fileExists(atPath: collision.path))
    }

    @Test("Repository evidence cannot overwrite the effective LCOV input")
    func rejectsLCOVInputCollision() throws {
        let fixture = try makeFixtureCopy()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let source = fixture.input.appendingPathComponent("Models.swift")
        let lcov = fixture.root.appendingPathComponent("coverage.info")
        let original = """
            TN:repository
            SF:\(source.path)
            DA:1,1
            end_of_record

            """
        try original.write(to: lcov, atomically: true, encoding: .utf8)

        let result = try runSwiftDebt([
            "debt", "analyze", fixture.root.path, "--jobs", "1", "--lcov", lcov.path,
            "--repository-evidence", lcov.path, "--debt-reference-time", "2026-09-12T00:00:00Z",
        ])

        #expect(result.status == 2)
        #expect(result.stderr.contains("Refusing to overwrite"))
        #expect(try String(contentsOf: lcov, encoding: .utf8) == original)
    }

    @Test("Case-only output names collide on case-insensitive macOS volumes")
    func rejectsCaseOnlyOutputCollision() throws {
        #if os(macOS)
            let fixture = try makeFixtureCopy()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let values = try fixture.root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            guard values.volumeSupportsCaseSensitiveNames == false else { return }
            let report = fixture.root.appendingPathComponent("Report.json")
            let repository = fixture.root.appendingPathComponent("report.json")

            let result = try runSwiftDebt([
                "analyze", fixture.input.path, "--jobs", "1", "--format", "json", "--output", report.path,
                "--repository-evidence", repository.path,
            ])

            #expect(result.status == 2)
            #expect(result.stderr.contains("another output"))
            #expect(!FileManager.default.fileExists(atPath: report.path))
            #expect(!FileManager.default.fileExists(atPath: repository.path))
        #endif
    }

    @Test("Lifecycle artifact and repository sidecar use the same filesystem identity guard")
    func rejectsCaseOnlyLifecycleCollision() throws {
        #if os(macOS)
            let fixture = try makeFixtureCopy()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let values = try fixture.root.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            guard values.volumeSupportsCaseSensitiveNames == false else { return }
            let lifecycle = fixture.root.appendingPathComponent("Lifecycle.json")
            let repository = fixture.root.appendingPathComponent("lifecycle.json")

            let result = try runSwiftDebt([
                "analyze", fixture.input.path, "--jobs", "1",
                "--lifecycle-artifact", lifecycle.path,
                "--repository-evidence", repository.path,
            ])

            #expect(result.status == 2)
            #expect(result.stderr.contains("another output"))
            #expect(!FileManager.default.fileExists(atPath: lifecycle.path))
            #expect(!FileManager.default.fileExists(atPath: repository.path))
        #endif
    }

    @Test("Canonical repository evidence cannot be forged through public constructors")
    func publicConstructionBoundary() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-debt-repository-api-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let probe = temporary.appendingPathComponent("Probe.swift")
        try """
        import SwiftDebtCore

        func forge() {
            _ = RepositoryRuleEvidence(
                ruleIdentity: "forged",
                semanticRevision: 1,
                name: "Forged",
                completionState: .complete,
                predicate: "none",
                capabilities: [],
                detections: [],
                issues: []
            )

            let digest: RepositoryDigest = fatalError()
            _ = RepositoryDetectionSelector(
                ruleIdentity: "forged",
                semanticRevision: 1,
                snapshotDigest: digest,
                location: SourceLocation(file: "Forged.swift", line: 1),
                evidenceFingerprint: digest
            )

            let selector: RepositoryDetectionSelector = fatalError()
            let explanation: RepositoryDetectionExplanation = fatalError()
            _ = RepositoryDetection(
                selector: selector,
                title: "Forged",
                primaryLocation: selector.location,
                summary: "forged",
                explanation: explanation
            )

            let snapshot: RepositorySnapshotIdentity = fatalError()
            let summary: RepositoryEvidenceSummary = fatalError()
            _ = RepositoryEvidenceReport(
                generator: "forged",
                snapshot: snapshot,
                rules: [],
                diagnostics: [],
                summary: summary
            )
        }
        """.write(to: probe, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", "-typecheck", "-I", try coreModuleSearchPath().path, probe.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        let diagnostic = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        #expect(process.terminationStatus != 0)
        #expect(diagnostic.contains("RepositoryRuleEvidence"))
        #expect(diagnostic.contains("RepositoryDetectionSelector"))
        #expect(diagnostic.contains("RepositoryDetection"))
        #expect(diagnostic.contains("RepositoryEvidenceReport"))
        #expect(
            diagnostic.contains("extra arguments")
                || diagnostic.contains("inaccessible")
                || diagnostic.contains("package")
        )
    }

}
