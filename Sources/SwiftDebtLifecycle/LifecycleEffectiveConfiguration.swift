import SwiftDebtCore

/// Canonical engine-captured dimensions behind a lifecycle configuration digest.
public struct LifecycleEffectiveConfiguration: Codable, Equatable, Sendable {
    public let sourceSelectionKind: SourceSelectionKind
    public let excludedSourcePrefixes: [String]
    public let maximumFileBytes: UInt64
    public let selectedRuleIdentities: [RuleIdentity]

    package init(
        sourceSelectionKind: SourceSelectionKind,
        excludedSourcePrefixes: [String],
        maximumFileBytes: Int,
        selectedRuleIdentities: [RuleIdentity]
    ) throws {
        guard maximumFileBytes > 0 else {
            throw LifecycleContractError.invalidSnapshot(
                "Effective configuration maximumFileBytes must be positive."
            )
        }
        try self.init(
            sourceSelectionKind: sourceSelectionKind,
            excludedSourcePrefixes: excludedSourcePrefixes,
            maximumFileBytes: UInt64(maximumFileBytes),
            selectedRuleIdentities: selectedRuleIdentities
        )
    }

    private init(
        sourceSelectionKind: SourceSelectionKind,
        excludedSourcePrefixes: [String],
        maximumFileBytes: UInt64,
        selectedRuleIdentities: [RuleIdentity]
    ) throws {
        let exclusions = excludedSourcePrefixes.sorted()
        let rules = selectedRuleIdentities.sorted { $0.description < $1.description }
        guard maximumFileBytes > 0,
            Set(exclusions).count == exclusions.count,
            exclusions.allSatisfy(Self.isValidExclusion),
            Set(rules).count == rules.count,
            !rules.isEmpty
        else {
            throw LifecycleContractError.invalidSnapshot(
                "Effective configuration requires canonical exclusions, positive file size, and unique selected rules."
            )
        }
        self.sourceSelectionKind = sourceSelectionKind
        self.excludedSourcePrefixes = exclusions
        self.maximumFileBytes = maximumFileBytes
        self.selectedRuleIdentities = rules
    }

    package func fingerprint() throws -> LifecycleDigest {
        var input = LifecycleDigestInput()
        input.append("swiftdebt-lifecycle-configuration-v2")
        input.append("source-discovery-policy-v1")
        input.append(sourceSelectionKind.rawValue)
        input.append(maximumFileBytes.description)
        input.append(UInt64(excludedSourcePrefixes.count))
        for exclusion in excludedSourcePrefixes { input.append(exclusion) }
        input.append(UInt64(selectedRuleIdentities.count))
        for rule in selectedRuleIdentities { input.append(rule.description) }
        return try LifecycleDigest(value: input.hexDigest())
    }

    package func differingDimensions(
        from prior: LifecycleEffectiveConfiguration
    ) -> [LifecycleConfigurationDimension] {
        var dimensions: [LifecycleConfigurationDimension] = []
        if sourceSelectionKind != prior.sourceSelectionKind { dimensions.append(.sourceSelectionKind) }
        if excludedSourcePrefixes != prior.excludedSourcePrefixes { dimensions.append(.excludedSourcePrefixes) }
        if maximumFileBytes != prior.maximumFileBytes { dimensions.append(.maximumFileBytes) }
        if selectedRuleIdentities != prior.selectedRuleIdentities { dimensions.append(.selectedRuleIdentities) }
        return dimensions
    }

    package func satisfies(
        _ condition: ConfigurationCompatibilityCondition,
        comparedFrom prior: LifecycleEffectiveConfiguration
    ) -> Bool {
        switch condition {
        case .maximumFileBytesNondecreasing:
            maximumFileBytes >= prior.maximumFileBytes
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sourceSelectionKind
        case excludedSourcePrefixes
        case maximumFileBytes
        case selectedRuleIdentities
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            let exclusions = try values.decode([String].self, forKey: .excludedSourcePrefixes)
            let rules = try values.decode([String].self, forKey: .selectedRuleIdentities)
                .map(Self.ruleIdentity)
            let canonicalExclusions = exclusions.sorted()
            let canonicalRules = rules.sorted { $0.description < $1.description }
            guard exclusions == canonicalExclusions, rules == canonicalRules else {
                throw LifecycleContractError.invalidSnapshot(
                    "Effective configuration dimensions must use canonical order."
                )
            }
            try self.init(
                sourceSelectionKind: values.decode(SourceSelectionKind.self, forKey: .sourceSelectionKind),
                excludedSourcePrefixes: exclusions,
                maximumFileBytes: values.decode(UInt64.self, forKey: .maximumFileBytes),
                selectedRuleIdentities: rules
            )
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .sourceSelectionKind,
                in: values,
                debugDescription: String(describing: error)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(sourceSelectionKind, forKey: .sourceSelectionKind)
        try values.encode(excludedSourcePrefixes, forKey: .excludedSourcePrefixes)
        try values.encode(maximumFileBytes, forKey: .maximumFileBytes)
        try values.encode(selectedRuleIdentities.map(\.description), forKey: .selectedRuleIdentities)
    }

    private static func ruleIdentity(_ value: String) throws -> RuleIdentity {
        guard let separator = value.lastIndex(of: "."), separator != value.startIndex else {
            throw LifecycleContractError.invalidSnapshot(
                "Effective configuration contains invalid Rule Identity \(value)."
            )
        }
        let namespaceValue = String(value[..<separator])
        let idValue = String(value[value.index(after: separator)...])
        guard let namespace = RuleNamespace(namespaceValue), let id = RuleID(idValue) else {
            throw LifecycleContractError.invalidSnapshot(
                "Effective configuration contains invalid Rule Identity \(value)."
            )
        }
        return RuleIdentity(namespace: namespace, id: id)
    }

    private static func isValidExclusion(_ value: String) -> Bool {
        !value.isEmpty
            && !value.hasPrefix("/")
            && !value.split(separator: "/").contains("..")
            && !value.contains("*")
            && !value.contains("?")
            && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
    }
}
