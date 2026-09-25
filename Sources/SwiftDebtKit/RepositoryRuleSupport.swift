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

func detectionFingerprint(
    ruleIdentity: String,
    values: [String],
    units: [RepositoryComparedUnit]
) throws -> RepositoryDigest {
    var hasher = RepositorySHA256()
    hasher.updateFramed(ruleIdentity)
    for value in values {
        hasher.updateFramed(value)
    }
    for unit in units.sorted(by: comparedUnitOrder) {
        hasher.updateFramed(unit.kind.rawValue)
        hasher.updateFramed(unit.displayName)
        hasher.updateFramed(unit.location.file)
        hasher.updateFramed(String(unit.location.line))
        hasher.updateFramed(String(unit.location.column))
    }
    return try RepositoryDigest(value: hasher.finalizeHex())
}
