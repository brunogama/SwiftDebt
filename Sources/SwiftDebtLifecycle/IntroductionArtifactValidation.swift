extension LifecycleArtifact {
    func validateIntroductionConclusions() throws {
        let evaluator = IntroductionConclusionEvaluator()
        for finding in findings {
            let conclusions = introductionConclusions.filter { $0.findingID == finding.id }
            guard
                conclusions.enumerated().allSatisfy({ index, conclusion in
                    conclusion.attempt == UInt(index + 1)
                })
            else {
                throw LifecycleContractError.invalidArtifact(
                    "Introduction attempts for Finding \(finding.id) must be append-only and contiguous."
                )
            }
            guard
                conclusions.indices.allSatisfy({ index in
                    !conclusions[..<index].contains(where: { $0.evidence == conclusions[index].evidence })
                })
            else {
                throw LifecycleContractError.invalidArtifact(
                    "A Finding cannot persist duplicate Introduction evidence."
                )
            }
            for conclusion in conclusions {
                switch conclusion.evidenceContract {
                case .legacySchemaTwo:
                    guard conclusion.semanticComparisons.isEmpty else {
                        throw LifecycleContractError.invalidArtifact("Legacy introduction asserted semantic evidence.")
                    }
                    try LegacyIntroductionConclusionEvaluator().validate(conclusion, artifact: self)
                case .semanticComparisonV1:
                    try evaluator.validate(conclusion, artifact: self)
                }
            }
        }
        let findingIDs = Set(findings.map(\.id))
        guard introductionConclusions.allSatisfy({ findingIDs.contains($0.findingID) }) else {
            throw LifecycleContractError.invalidArtifact(
                "An Introduction Conclusion references a missing Finding."
            )
        }
    }
}
