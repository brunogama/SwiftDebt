extension RepositoryRuleEvidence: Codable {
    private enum CodingKeys: String, CodingKey {
        case ruleIdentity
        case semanticRevision
        case name
        case qualification
        case completionState
        case predicate
        case capabilities
        case detections
        case issues
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ruleIdentity = try values.decode(String.self, forKey: .ruleIdentity)
        semanticRevision = try values.decode(UInt.self, forKey: .semanticRevision)
        name = try values.decode(String.self, forKey: .name)
        qualification = try values.decode(RepositoryRuleQualification.self, forKey: .qualification)
        completionState = try values.decode(RepositoryRuleCompletionState.self, forKey: .completionState)
        predicate = try values.decode(String.self, forKey: .predicate)
        capabilities = try values.decode([RepositoryCapabilityEvidence].self, forKey: .capabilities)
        detections = try values.decode([RepositoryDetection].self, forKey: .detections)
        issues = try values.decode([RepositoryEvidenceIssue].self, forKey: .issues)

        guard semanticRevision > 0,
            hasRepositoryEvidenceContent(ruleIdentity),
            hasRepositoryEvidenceContent(name),
            hasRepositoryEvidenceContent(predicate),
            !capabilities.isEmpty,
            Set(capabilities.map(\.capability)).count == capabilities.count,
            capabilities.allSatisfy({ capability in
                hasRepositoryEvidenceContent(capability.capability)
                    && hasRepositoryEvidenceContent(capability.provider.name)
                    && hasRepositoryEvidenceContent(capability.provider.version)
            }),
            detections.allSatisfy({ detection in
                detection.selector.ruleIdentity == ruleIdentity
                    && detection.selector.semanticRevision == semanticRevision
                    && detection.primaryLocation == detection.selector.location
            })
        else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Repository rule evidence has invalid identity or broken references."
                )
            )
        }

        let capabilitiesComplete = capabilities.allSatisfy { $0.state == .available }
        let stateIsConsistent: Bool
        switch completionState {
        case .complete:
            stateIsConsistent = issues.isEmpty && capabilitiesComplete
        case .incomplete:
            stateIsConsistent = !issues.isEmpty && !capabilitiesComplete
        }
        guard stateIsConsistent else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Repository rule completion contradicts its issues or capabilities."
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(ruleIdentity, forKey: .ruleIdentity)
        try values.encode(semanticRevision, forKey: .semanticRevision)
        try values.encode(name, forKey: .name)
        try values.encode(qualification, forKey: .qualification)
        try values.encode(completionState, forKey: .completionState)
        try values.encode(predicate, forKey: .predicate)
        try values.encode(capabilities, forKey: .capabilities)
        try values.encode(detections, forKey: .detections)
        try values.encode(issues, forKey: .issues)
    }
}

extension RepositoryEvidenceReport: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reportKind
        case generator
        case snapshot
        case rules
        case diagnostics
        case summary
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == RepositoryEvidenceReportSchema.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: RepositoryEvidenceContractError.unsupportedSchemaVersion(schemaVersion).description
            )
        }
        let reportKind = try values.decode(String.self, forKey: .reportKind)
        guard reportKind == RepositoryEvidenceReportSchema.reportKind else {
            throw DecodingError.dataCorruptedError(
                forKey: .reportKind,
                in: values,
                debugDescription: RepositoryEvidenceContractError.unsupportedReportKind(reportKind).description
            )
        }
        self.schemaVersion = schemaVersion
        self.reportKind = reportKind
        generator = try values.decode(String.self, forKey: .generator)
        snapshot = try values.decode(RepositorySnapshotIdentity.self, forKey: .snapshot)
        rules = try values.decode([RepositoryRuleEvidence].self, forKey: .rules)
        diagnostics = try values.decode([AnalysisDiagnostic].self, forKey: .diagnostics)
        summary = try values.decode(RepositoryEvidenceSummary.self, forKey: .summary)

        let sourceFilesAreCanonical =
            !snapshot.sourceFiles.isEmpty
            && Set(snapshot.sourceFiles).count == snapshot.sourceFiles.count
            && snapshot.sourceFiles == snapshot.sourceFiles.sorted()
            && snapshot.sourceFiles.allSatisfy { path in
                guard let canonical = try? SourcePath(path) else { return false }
                return canonical.rawValue == path
            }
        let ruleIdentities = rules.map(\.ruleIdentity)
        let summaryMatches =
            summary.sourceFileCount == snapshot.sourceFiles.count
            && summary.completeRuleCount == rules.count { $0.completionState == .complete }
            && summary.incompleteRuleCount == rules.count { $0.completionState == .incomplete }
            && summary.detectionCount == rules.flatMap(\.detections).count
        let parseFailuresAreIncomplete =
            !diagnostics.contains { $0.severity == .error }
            || rules.allSatisfy { rule in
                rule.completionState == .incomplete && rule.issues.contains { $0.code == "parse-failed" }
            }
        guard hasRepositoryEvidenceContent(generator),
            sourceFilesAreCanonical,
            !rules.isEmpty,
            Set(ruleIdentities).count == rules.count,
            ruleIdentities == ruleIdentities.sorted(),
            rules.flatMap(\.detections).allSatisfy({ detection in
                detection.selector.snapshotDigest == snapshot.contentDigest
            }),
            hasRepositoryEvidenceContent(summary.currentSnapshotNotice),
            summaryMatches,
            parseFailuresAreIncomplete
        else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Repository evidence report has inconsistent derived state or provenance."
                )
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(reportKind, forKey: .reportKind)
        try values.encode(generator, forKey: .generator)
        try values.encode(snapshot, forKey: .snapshot)
        try values.encode(rules, forKey: .rules)
        try values.encode(diagnostics, forKey: .diagnostics)
        try values.encode(summary, forKey: .summary)
    }
}
