import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("Pipeline service")
struct PipelineServiceTests {
    @Test func runsSeriallyAndRetainsEvidenceAfterFailure() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("failed-check-finished")
        let artifacts = root.appendingPathComponent("artifacts")
        let configuration = makeConfiguration(commands: [
            shell(.staticAnalysis, "printf 'standard output'; printf 'standard error' >&2"),
            shell(
                .architecture,
                "printf 'architecture failed' >&2; printf ready > \"$1\"; exit 7",
                trailing: [marker.path]
            ),
            shell(
                .unit,
                "test -f \"$1\" && printf 'continued after failure'",
                trailing: [marker.path]
            ),
        ])

        let report = try PipelineService().run(
            configuration: configuration,
            workingDirectory: root,
            artifactsDirectory: artifacts
        )

        try expectPipelineEvidence(
            report: report,
            configuration: configuration,
            artifacts: artifacts
        )
    }

    @Test func missingBindingsStayUnavailableAndUnplannedCommandsDoNotRun() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let emptyArtifacts = root.appendingPathComponent("empty-artifacts")
        let empty = try PipelineService().run(
            configuration: makeConfiguration(),
            workingDirectory: root,
            artifactsDirectory: emptyArtifacts
        )
        #expect(empty.evaluation.verdict == .inconclusive)
        #expect(empty.evaluation.results.allSatisfy { $0.status == .unavailable })
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: emptyArtifacts.path).sorted()
                == (["configuration.json", "plan.json", "report.json"]
                + empty.plan.requirements.map { "\($0.check.rawValue).result.json" }).sorted())

        let marker = root.appendingPathComponent("unplanned-ran")
        let artifacts = root.appendingPathComponent("unplanned-artifacts")
        let report = try PipelineService().run(
            configuration: makeConfiguration(commands: [
                shell(.dependencies, "printf ran > \"$1\"", trailing: [marker.path])
            ]),
            workingDirectory: root,
            artifactsDirectory: artifacts
        )
        #expect(!report.evaluation.results.contains { $0.check == .dependencies })
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: artifacts.appendingPathComponent("dependencies.stdout.log").path))
    }

    @Test func rejectsInvalidConfigurationBeforeArtifactsOrExecution() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let valid = shell(.staticAnalysis, "exit 0")
        let invalidConfigurations = [
            makeConfiguration(schemaVersion: 2),
            makeConfiguration(commands: [valid, valid]),
            makeConfiguration(commands: [.init(check: .unit, executable: "")]),
            makeConfiguration(commands: [.init(check: .unit, executable: "bin/sh")]),
            makeConfiguration(commands: [.init(check: .unit, executable: "/bin/\0sh")]),
            makeInvalidTimeoutConfiguration(0),
            makeInvalidTimeoutConfiguration(.nan),
            makeInvalidTimeoutConfiguration(86_401),
            makeConfiguration(commands: [
                .init(check: .unit, executable: "/bin/sh", arguments: ["bad\0arg"])
            ]),
        ]
        for configuration in invalidConfigurations {
            #expect(throws: (any Error).self) {
                _ = try PipelineService().plan(configuration: configuration)
            }
        }

        let marker = root.appendingPathComponent("must-not-run")
        let artifacts = root.appendingPathComponent("invalid-artifacts")
        let lateInvalid = makeConfiguration(commands: [
            shell(.staticAnalysis, "printf ran > \"$1\"", trailing: [marker.path]),
            .init(check: .architecture, executable: "relative-command"),
        ])
        #expect(throws: (any Error).self) {
            _ = try PipelineService().run(
                configuration: lateInvalid,
                workingDirectory: root,
                artifactsDirectory: artifacts
            )
        }
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: artifacts.path))
    }

    @Test func refusesArtifactReuseWithoutChangingExistingContents() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let artifacts = root.appendingPathComponent("artifacts")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: false)
        let sentinel = artifacts.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let marker = root.appendingPathComponent("must-not-run")

        #expect(throws: (any Error).self) {
            _ = try PipelineService().run(
                configuration: makeConfiguration(commands: [
                    shell(.staticAnalysis, "printf ran > \"$1\"", trailing: [marker.path])
                ]),
                workingDirectory: root,
                artifactsDirectory: artifacts
            )
        }
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "keep")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test(.timeLimit(.minutes(1))) func forceKillsACommandThatIgnoresTermination() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let artifacts = root.appendingPathComponent("artifacts")
        let command = PipelineCommand(
            check: .staticAnalysis,
            executable: "/bin/sh",
            arguments: ["-c", "trap '' TERM; printf ready; while :; do :; done"],
            timeoutSeconds: 0.2
        )
        let report = try PipelineService().run(
            configuration: makeConfiguration(commands: [command]),
            workingDirectory: root,
            artifactsDirectory: artifacts
        )

        #expect(status(of: .staticAnalysis, in: report) == .timedOut)
        #expect(try text("staticAnalysis.stdout.log", in: artifacts) == "ready")
        #expect(
            FileManager.default.fileExists(
                atPath: artifacts.appendingPathComponent("report.json").path))
    }
}
