import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

extension RepositorySyntaxCacheCLIWorkflowTests {
    @Test("In-repository cache outputs do not change repository provenance")
    func inRepositoryOutputsRemainProvenanceNeutral() throws {
        let fixture = try makeCacheFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try initializeGitRepository(fixture.repository)

        let outputDirectory = fixture.repository.appendingPathComponent(
            ".swift-debt",
            isDirectory: true
        )
        let evidence = outputDirectory.appendingPathComponent("repository-evidence.json")
        let cache = outputDirectory.appendingPathComponent("repository-facts.json")
        let activity = outputDirectory.appendingPathComponent("repository-cache-report.json")
        let arguments = [
            "analyze", fixture.repository.path, "--format", "json", "--jobs", "1",
            "--repository-evidence", evidence.path,
            "--repository-cache", cache.path,
            "--repository-cache-report", activity.path,
        ]

        let first = try runSwiftDebt(arguments)
        let firstEvidence = try Data(contentsOf: evidence)
        let firstReport = try JSONDecoder().decode(
            RepositoryEvidenceReport.self,
            from: firstEvidence
        )
        let firstActivity = try JSONDecoder().decode(
            RepositorySyntaxCacheReport.self,
            from: Data(contentsOf: activity)
        )

        let second = try runSwiftDebt(arguments)
        let secondEvidence = try Data(contentsOf: evidence)
        let secondReport = try JSONDecoder().decode(
            RepositoryEvidenceReport.self,
            from: secondEvidence
        )
        let secondActivity = try JSONDecoder().decode(
            RepositorySyntaxCacheReport.self,
            from: Data(contentsOf: activity)
        )

        #expect(first.status == 0)
        #expect(second.status == 0)
        #expect(firstEvidence == secondEvidence)
        #expect(firstReport.snapshot.versionControl?.workingTreeState == .clean)
        #expect(secondReport.snapshot.versionControl?.workingTreeState == .clean)
        #expect(firstActivity.disposition == .coldRebuild)
        #expect(secondActivity.disposition == .warmReuse)
    }
}
