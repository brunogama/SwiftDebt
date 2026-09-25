import SwiftDebtCore

let repositorySyntaxProvider = RepositoryProviderIdentity(name: "SwiftSyntax", version: "602.0.0")

func repositoryCapability(
    _ name: String,
    issues: [RepositoryEvidenceIssue]
) throws -> RepositoryCapabilityEvidence {
    if issues.isEmpty {
        return try RepositoryCapabilityEvidence(
            capability: name,
            state: .available,
            provider: repositorySyntaxProvider
        )
    }
    let issue = try RepositoryEvidenceIssue(
        code: "repository-analysis-incomplete",
        message: issues.map(\.message).joined(separator: " ")
    )
    return try RepositoryCapabilityEvidence(
        capability: name,
        state: .failed,
        provider: repositorySyntaxProvider,
        issue: issue
    )
}
