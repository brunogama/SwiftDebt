func repositorySourceLocationOrder(_ lhs: SourceLocation, _ rhs: SourceLocation) -> Bool {
    if lhs.file != rhs.file { return lhs.file < rhs.file }
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    return lhs.column < rhs.column
}

func repositoryComparedUnitOrder(_ lhs: RepositoryComparedUnit, _ rhs: RepositoryComparedUnit) -> Bool {
    if repositorySourceLocationOrder(lhs.location, rhs.location) { return true }
    if repositorySourceLocationOrder(rhs.location, lhs.location) { return false }
    if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
    return lhs.displayName < rhs.displayName
}

func repositoryObservedFactOrder(_ lhs: RepositoryObservedFact, _ rhs: RepositoryObservedFact) -> Bool {
    if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
    if lhs.value != rhs.value { return lhs.value < rhs.value }
    if lhs.evidenceClass.rawValue != rhs.evidenceClass.rawValue {
        return lhs.evidenceClass.rawValue < rhs.evidenceClass.rawValue
    }
    return locationListPrecedes(lhs.locations, rhs.locations)
}

func repositoryEvidenceClassOrder(_ lhs: RepositoryEvidenceClass, _ rhs: RepositoryEvidenceClass) -> Bool {
    repositoryEvidenceClassRank(lhs) < repositoryEvidenceClassRank(rhs)
}

func repositoryDetectionOrder(_ lhs: RepositoryDetection, _ rhs: RepositoryDetection) -> Bool {
    let left = lhs.selector
    let right = rhs.selector
    if left.ruleIdentity != right.ruleIdentity { return left.ruleIdentity < right.ruleIdentity }
    if left.semanticRevision != right.semanticRevision { return left.semanticRevision < right.semanticRevision }
    if repositorySourceLocationOrder(left.location, right.location) { return true }
    if repositorySourceLocationOrder(right.location, left.location) { return false }
    return left.evidenceFingerprint.value < right.evidenceFingerprint.value
}

func repositoryIssueOrder(_ lhs: RepositoryEvidenceIssue, _ rhs: RepositoryEvidenceIssue) -> Bool {
    if lhs.code != rhs.code { return lhs.code < rhs.code }
    return lhs.message < rhs.message
}

func repositoryCapabilityOrder(_ lhs: RepositoryCapabilityEvidence, _ rhs: RepositoryCapabilityEvidence) -> Bool {
    if lhs.capability != rhs.capability { return lhs.capability < rhs.capability }
    if lhs.provider.name != rhs.provider.name { return lhs.provider.name < rhs.provider.name }
    if lhs.provider.version != rhs.provider.version { return lhs.provider.version < rhs.provider.version }
    return lhs.state.rawValue < rhs.state.rawValue
}

func repositoryDiagnosticOrder(_ lhs: AnalysisDiagnostic, _ rhs: AnalysisDiagnostic) -> Bool {
    if repositorySourceLocationOrder(lhs.location, rhs.location) { return true }
    if repositorySourceLocationOrder(rhs.location, lhs.location) { return false }
    if lhs.severity.rawValue != rhs.severity.rawValue { return lhs.severity.rawValue < rhs.severity.rawValue }
    return lhs.message < rhs.message
}

package func repositoryEvidenceFingerprint(
    ruleIdentity: String,
    semanticRevision: UInt,
    decisiveFacts: [RepositoryObservedFact],
    comparedUnits: [RepositoryComparedUnit]
) throws -> RepositoryDigest {
    var hasher = RepositorySHA256()
    hasher.updateFramed("swiftdebt-repository-evidence-fingerprint-v1")
    hasher.updateFramed(ruleIdentity)
    hasher.updateFramed(String(semanticRevision))

    let facts = decisiveFacts.sorted(by: repositoryObservedFactOrder)
    hasher.updateFramed("facts")
    hasher.updateFramed(String(facts.count))
    for fact in facts {
        hasher.updateFramed(fact.kind)
        hasher.updateFramed(fact.value)
        hasher.updateFramed(fact.evidenceClass.rawValue)
        let locations = fact.locations.sorted(by: repositorySourceLocationOrder)
        hasher.updateFramed(String(locations.count))
        for location in locations {
            hash(location, into: &hasher)
        }
    }

    let units = comparedUnits.sorted(by: repositoryComparedUnitOrder)
    hasher.updateFramed("units")
    hasher.updateFramed(String(units.count))
    for unit in units {
        hasher.updateFramed(unit.kind.rawValue)
        hasher.updateFramed(unit.displayName)
        hash(unit.location, into: &hasher)
    }
    return try RepositoryDigest(value: hasher.finalizeHex())
}

private func hash(_ location: SourceLocation, into hasher: inout RepositorySHA256) {
    hasher.updateFramed(location.file)
    hasher.updateFramed(String(location.line))
    hasher.updateFramed(String(location.column))
}

private func locationListPrecedes(_ lhs: [SourceLocation], _ rhs: [SourceLocation]) -> Bool {
    for (left, right) in zip(lhs, rhs) {
        if repositorySourceLocationOrder(left, right) { return true }
        if repositorySourceLocationOrder(right, left) { return false }
    }
    return lhs.count < rhs.count
}

private func repositoryEvidenceClassRank(_ value: RepositoryEvidenceClass) -> Int {
    switch value {
    case .syntax: 0
    case .metric: 1
    case .structural: 2
    case .relationship: 3
    case .compilerBacked: 4
    case .similarity: 5
    }
}
