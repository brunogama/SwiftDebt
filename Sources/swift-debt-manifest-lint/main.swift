import Foundation
import SwiftDebtCore

/// Standalone entry point that wires ``RuleManifestParser`` into an actual
/// SwiftPM build-time failure (R2 TASK-009). Invoked by
/// `RuleManifestValidationPlugin` as a prebuild command against a real
/// manifest file; a non-empty error list causes this process to exit
/// non-zero, which fails the enclosing `swift build`.
///
/// Usage: swift-debt-manifest-lint <path-to-manifest.yaml> [stamp-output-path]
///
/// The optional stamp path is written on success only, so SwiftPM's build
/// plugin can declare it as an output file and skip re-running this check
/// when the manifest has not changed.

guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: swift-debt-manifest-lint <path-to-manifest.yaml> [stamp-output-path]\n".utf8))
    exit(2)
}

let manifestPath = CommandLine.arguments[1]
let stampPath = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : nil

guard let yaml = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
    FileHandle.standardError.write(
        Data("swift-debt-manifest-lint: unable to read manifest at '\(manifestPath)'\n".utf8))
    exit(2)
}

let (definitions, errors) = RuleManifestParser.collectErrors(yaml: yaml)

guard errors.isEmpty else {
    let header = "swift-debt-manifest-lint: \(errors.count) error(s) in '\(manifestPath)':\n"
    FileHandle.standardError.write(Data(header.utf8))
    for error in errors {
        FileHandle.standardError.write(Data("  - \(error.description)\n".utf8))
    }
    exit(1)
}

FileHandle.standardOutput.write(
    Data("swift-debt-manifest-lint: '\(manifestPath)' OK (\(definitions.count) rule(s))\n".utf8))
if let stampPath {
    try? "ok\n".write(toFile: stampPath, atomically: true, encoding: .utf8)
}
exit(0)
