import Foundation
import SwiftDebtLifecycle
import Testing

@Suite("R3 audit export CLI")
struct LifecycleAuditExportCLIWorkflowTests {
    @Test("Validated audit export is canonical, complete, and read-only")
    func canonicalAuditExport() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        let first = try makeObservation(
            id: "audit-export-first",
            sequence: 1,
            rules: [LifecycleRuleV1(mode: .committed(1))]
        )
        let second = try makeObservation(
            id: "audit-export-second",
            sequence: 2,
            predecessor: first.id.rawValue,
            rules: [LifecycleRuleV1(mode: .committed(0))]
        )
        _ = try store.ingest(first)
        _ = try store.ingest(second)
        let artifact = try store.load()
        let before = try Data(contentsOf: fixture.url)

        let result = try runLifecycleCLI(["lifecycle", "export", fixture.url.path])

        #expect(result.status == 0)
        #expect(result.standardError.isEmpty)
        let canonicalBytes = try store.canonicalData(for: artifact)
        #expect(Data(result.standardOutput.utf8) == canonicalBytes)
        #expect(try JSONDecoder().decode(LifecycleArtifact.self, from: Data(result.standardOutput.utf8)) == artifact)
        #expect(try Data(contentsOf: fixture.url) == before)
    }

    @Test("Audit export rejects corrupt history without writing a replacement")
    func corruptAuditExport() throws {
        let fixture = try TemporaryLifecycleArtifact()
        let store = LifecycleArtifactStore(artifactURL: fixture.url)
        _ = try store.ingest(
            makeObservation(
                id: "audit-export-corrupt",
                sequence: 1,
                rules: [LifecycleRuleV1(mode: .committed(1))]
            ))
        let corrupt = Data("{\"schemaVersion\":99}".utf8)
        try corrupt.write(to: fixture.url, options: .atomic)

        let result = try runLifecycleCLI(["lifecycle", "export", fixture.url.path])

        #expect(result.status == 2)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("Unsupported lifecycle artifact schema version 99"))
        #expect(try Data(contentsOf: fixture.url) == corrupt)
    }
}
