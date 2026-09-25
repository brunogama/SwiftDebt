import Foundation
import SwiftDebtCore

extension RepositoryAnalysisCLIWorkflowTests {
    func makeFixtureCopy(named name: String = "Positive") throws -> (
        root: URL,
        input: URL,
        sidecar: URL,
        gatedSidecar: URL
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-debt-repository-cli-\(UUID().uuidString)",
            isDirectory: true
        )
        let input = root.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixtureRoot.appendingPathComponent(name), to: input)
        return (
            root,
            input,
            root.appendingPathComponent("repository-evidence.json"),
            root.appendingPathComponent("gated-repository-evidence.json")
        )
    }

    func repositorySection(_ output: String) -> String {
        guard let marker = output.range(of: "REPOSITORY EVIDENCE (EXPERIMENTAL)\n") else { return "" }
        return String(output[marker.lowerBound...])
    }

    func fixtureText(_ name: String) throws -> String {
        try String(contentsOf: fixtureRoot.appendingPathComponent(name), encoding: .utf8)
    }

    func normalizingRepositoryGenerator(_ json: String) throws -> String {
        let report = try JSONDecoder().decode(RepositoryEvidenceReport.self, from: Data(json.utf8))
        let value = #""generator" : "\#(report.generator)""#
        guard json.components(separatedBy: value).count == 2 else {
            throw RepositoryAPITestError("Repository evidence must contain one canonical generator field")
        }
        return json.replacingOccurrences(
            of: value,
            with: #""generator" : "SwiftDebt <release-version>""#
        )
    }

    var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RepositoryAnalysis")
    }

    func coreModuleSearchPath() throws -> URL {
        let build = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build")
        guard let enumerator = FileManager.default.enumerator(at: build, includingPropertiesForKeys: nil) else {
            throw RepositoryAPITestError("Could not enumerate \(build.path)")
        }
        let modules = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.lastPathComponent == "SwiftDebtCore.swiftmodule" else { return nil }
            return url.deletingLastPathComponent()
        }.sorted { lhs, rhs in
            let lhsPreferred = lhs.path.contains("/Products/Debug") || lhs.path.contains("/debug/Modules")
            let rhsPreferred = rhs.path.contains("/Products/Debug") || rhs.path.contains("/debug/Modules")
            if lhsPreferred != rhsPreferred { return lhsPreferred }
            return lhs.path < rhs.path
        }
        guard let modules = modules.first else {
            throw RepositoryAPITestError("Could not locate SwiftDebtCore.swiftmodule under \(build.path)")
        }
        return modules
    }
}

private struct RepositoryAPITestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
