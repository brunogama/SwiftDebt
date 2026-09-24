import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

func temporaryGitTestDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "swift-debt-git-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

func initializeGitRepository(at root: URL) throws {
    try runGitFixture(["init"], root: root)
    try runGitFixture(["config", "user.name", "Test User"], root: root)
    try runGitFixture(["config", "user.email", "test@example.test"], root: root)
}

func writeGitFixture(_ text: String, name: String, root: URL) throws {
    let url = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func commitGitFixture(root: URL, message: String, authorEmail: String, timestamp: String) throws {
    try runGitFixture(["add", "."], root: root)
    try runGitFixture(
        ["commit", "-m", message],
        root: root,
        environment: [
            "GIT_AUTHOR_NAME": "Test User",
            "GIT_AUTHOR_EMAIL": authorEmail,
            "GIT_AUTHOR_DATE": timestamp,
            "GIT_COMMITTER_NAME": "Test User",
            "GIT_COMMITTER_EMAIL": authorEmail,
            "GIT_COMMITTER_DATE": timestamp,
        ]
    )
}

func runGitFixture(_ arguments: [String], root: URL, environment: [String: String] = [:]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", root.path] + arguments
    process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let data = output.fileHandleForReading.readDataToEndOfFile()
        throw TestGitError(message: String(decoding: data, as: UTF8.self))
    }
}

func gitFixtureEntity(id: String, file: String) -> DebtEntity {
    DebtEntity(
        id: id,
        displayName: id,
        level: .file,
        location: DebtLocation(module: "Workspace", file: file)
    )
}

enum UnavailableRepositoryCase: String, CaseIterable, CustomTestStringConvertible {
    case nonRepository
    case noHistory
    case shallow

    var testDescription: String { rawValue }

    var reasonFragment: String {
        switch self {
        case .nonRepository: "not a git repository"
        case .noHistory: "no commits"
        case .shallow: "shallow git history"
        }
    }

    func makeRepository(in root: URL) throws -> URL {
        switch self {
        case .nonRepository:
            return root
        case .noHistory:
            try initializeGitRepository(at: root)
            return root
        case .shallow:
            let source = root.appendingPathComponent("source", isDirectory: true)
            let clone = root.appendingPathComponent("clone", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try initializeGitRepository(at: source)
            try writeGitFixture("struct Shallow {}\n", name: "Sources/Shallow.swift", root: source)
            try commitGitFixture(
                root: source,
                message: "feat: seed shallow source",
                authorEmail: "shallow@example.test",
                timestamp: "2026-09-01T00:00:00Z"
            )
            try cloneGitRepository(source: source, destination: clone)
            return clone
        }
    }

    private func cloneGitRepository(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "clone", "--depth", "1", "file://\(source.path)", destination.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            throw TestGitError(message: String(decoding: data, as: UTF8.self))
        }
    }
}

final class RecordingGitRunner: GitHistoryProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executableURL: URL
        let arguments: [String]
        let workingDirectory: URL
        let timeoutSeconds: TimeInterval
    }

    private let lock = NSLock()
    private var responses: [GitHistoryProcessResult] = []
    private var recordedCalls: [Call] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    func enqueue(_ response: GitHistoryProcessResult) {
        lock.lock()
        defer { lock.unlock() }
        responses.append(response)
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval
    ) -> GitHistoryProcessResult {
        lock.lock()
        defer { lock.unlock() }
        recordedCalls.append(
            .init(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: timeoutSeconds
            ))
        if responses.isEmpty {
            return GitHistoryProcessResult(exitCode: 1, stdout: "", stderr: "missing response", timedOut: false)
        }
        return responses.removeFirst()
    }
}

struct TestGitError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
