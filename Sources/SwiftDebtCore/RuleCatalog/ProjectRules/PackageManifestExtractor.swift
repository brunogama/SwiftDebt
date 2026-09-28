import Foundation

/// Errors raised while extracting facts from a SwiftPM manifest.
public enum PackageManifestExtractionError: Error, Sendable, Equatable {
    case manifestNotFound(String)
    case dumpPackageFailed(exitCode: Int32, stderr: String)
    case malformedDumpPackageOutput(String)
}

/// Minimal facts read from a `Package.swift` manifest via `swift package
/// dump-package` (research #71: "A `PackageAnalysisContext` can expose
/// manifest facts without contaminating source-local rule APIs" - addendum
/// J). This intentionally mirrors only the shape project-scope rules need
/// today, never the full `PackageDescription` surface.
public struct PackageManifestFacts: Sendable, Equatable {
    /// One target's declared build settings, reduced to the facts this
    /// pilot's rules need.
    public struct TargetSettings: Sendable, Equatable {
        public let targetName: String
        public let hasUnsafeFlags: Bool

        public init(targetName: String, hasUnsafeFlags: Bool) {
            self.targetName = targetName
            self.hasUnsafeFlags = hasUnsafeFlags
        }
    }

    public let packageName: String
    public let targets: [TargetSettings]

    public init(packageName: String, targets: [TargetSettings]) {
        self.packageName = packageName
        self.targets = targets
    }
}

/// Reads `Package.swift` manifest facts by shelling out to
/// `swift package dump-package`, which is the toolchain's own manifest
/// evaluator - this avoids re-implementing a `PackageDescription`
/// interpreter to answer a narrow, structural question (does any target
/// declare `.unsafeFlags(...)`).
///
/// No existing manifest-fact extractor was found elsewhere in this
/// repository (`Sources/SwiftDebtKit/SourceDiscovery.swift` only treats
/// `Package.swift` as a path to exclude from source discovery), so this is
/// a new, deliberately narrow utility.
public struct PackageManifestExtractor: Sendable {
    /// Result of running an external process, kept as a named type rather
    /// than a tuple to stay within this repository's tuple-size lint limit.
    struct ProcessResult: Sendable {
        let exitCode: Int32
        let stdout: Data
        let stderr: Data
    }

    private let processRunner: @Sendable (String, [String]) throws -> ProcessResult

    public init() {
        self.processRunner = Self.runProcess
    }

    /// For testing: inject a fake process runner instead of shelling out.
    init(
        processRunner: @escaping @Sendable (String, [String]) throws -> ProcessResult
    ) {
        self.processRunner = processRunner
    }

    /// Extracts manifest facts for the package rooted at `packageDirectory`
    /// (the directory containing `Package.swift`).
    public func extractFacts(packageDirectory: URL) throws -> PackageManifestFacts {
        let manifestPath = packageDirectory.appendingPathComponent("Package.swift").path
        guard FileManager.default.fileExists(atPath: manifestPath) else {
            throw PackageManifestExtractionError.manifestNotFound(manifestPath)
        }

        let result = try processRunner(
            "swift",
            ["package", "--package-path", packageDirectory.path, "dump-package"]
        )
        guard result.exitCode == 0 else {
            let message = String(data: result.stderr, encoding: .utf8) ?? ""
            throw PackageManifestExtractionError.dumpPackageFailed(
                exitCode: result.exitCode, stderr: message)
        }

        guard
            let root = try JSONSerialization.jsonObject(with: result.stdout) as? [String: Any]
        else {
            throw PackageManifestExtractionError.malformedDumpPackageOutput(
                "expected a JSON object from 'swift package dump-package'")
        }
        guard let packageName = root["name"] as? String else {
            throw PackageManifestExtractionError.malformedDumpPackageOutput(
                "manifest JSON is missing a top-level 'name'")
        }

        let targetsJSON = root["targets"] as? [[String: Any]] ?? []
        let targets: [PackageManifestFacts.TargetSettings] = targetsJSON.map { target in
            let targetName = target["name"] as? String ?? "<unnamed>"
            let settings = target["settings"] as? [[String: Any]] ?? []
            let hasUnsafeFlags = settings.contains { setting in
                guard let kind = setting["kind"] as? [String: Any] else { return false }
                return kind["unsafeFlags"] != nil
            }
            return PackageManifestFacts.TargetSettings(
                targetName: targetName, hasUnsafeFlags: hasUnsafeFlags)
        }

        return PackageManifestFacts(packageName: packageName, targets: targets)
    }

    private static func runProcess(
        _ launchPath: String,
        _ arguments: [String]
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [launchPath] + arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
