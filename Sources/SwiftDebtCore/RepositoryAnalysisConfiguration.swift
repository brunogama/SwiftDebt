public struct RepositoryAnalysisConfiguration: Codable, Equatable, Sendable {
    public static let standard = RepositoryAnalysisConfiguration(
        validatedMinimumDataClumpElements: 3,
        minimumDataClumpOccurrences: 2,
        minimumRepeatedSwitchOccurrences: 2,
        maximumSourceFiles: 10_000,
        maximumTotalSourceBytes: 256 * 1_024 * 1_024,
        maximumAnalysisUnitsPerRule: 50_000,
        maximumDataClumpComparisons: 250_000,
        maximumDetectionsPerRule: 10_000
    )

    public let minimumDataClumpElements: Int
    public let minimumDataClumpOccurrences: Int
    public let minimumRepeatedSwitchOccurrences: Int
    public let maximumSourceFiles: Int
    public let maximumTotalSourceBytes: Int
    public let maximumAnalysisUnitsPerRule: Int
    public let maximumDataClumpComparisons: Int
    public let maximumDetectionsPerRule: Int

    public init(
        minimumDataClumpElements: Int,
        minimumDataClumpOccurrences: Int,
        minimumRepeatedSwitchOccurrences: Int,
        maximumSourceFiles: Int,
        maximumTotalSourceBytes: Int,
        maximumAnalysisUnitsPerRule: Int,
        maximumDataClumpComparisons: Int,
        maximumDetectionsPerRule: Int
    ) throws {
        try Self.validate(
            minimumDataClumpElements: minimumDataClumpElements,
            minimumDataClumpOccurrences: minimumDataClumpOccurrences,
            minimumRepeatedSwitchOccurrences: minimumRepeatedSwitchOccurrences,
            maximumSourceFiles: maximumSourceFiles,
            maximumTotalSourceBytes: maximumTotalSourceBytes,
            maximumAnalysisUnitsPerRule: maximumAnalysisUnitsPerRule,
            maximumDataClumpComparisons: maximumDataClumpComparisons,
            maximumDetectionsPerRule: maximumDetectionsPerRule
        )
        self.init(
            validatedMinimumDataClumpElements: minimumDataClumpElements,
            minimumDataClumpOccurrences: minimumDataClumpOccurrences,
            minimumRepeatedSwitchOccurrences: minimumRepeatedSwitchOccurrences,
            maximumSourceFiles: maximumSourceFiles,
            maximumTotalSourceBytes: maximumTotalSourceBytes,
            maximumAnalysisUnitsPerRule: maximumAnalysisUnitsPerRule,
            maximumDataClumpComparisons: maximumDataClumpComparisons,
            maximumDetectionsPerRule: maximumDetectionsPerRule
        )
    }

    private init(
        validatedMinimumDataClumpElements minimumDataClumpElements: Int,
        minimumDataClumpOccurrences: Int,
        minimumRepeatedSwitchOccurrences: Int,
        maximumSourceFiles: Int,
        maximumTotalSourceBytes: Int,
        maximumAnalysisUnitsPerRule: Int,
        maximumDataClumpComparisons: Int,
        maximumDetectionsPerRule: Int
    ) {
        self.minimumDataClumpElements = minimumDataClumpElements
        self.minimumDataClumpOccurrences = minimumDataClumpOccurrences
        self.minimumRepeatedSwitchOccurrences = minimumRepeatedSwitchOccurrences
        self.maximumSourceFiles = maximumSourceFiles
        self.maximumTotalSourceBytes = maximumTotalSourceBytes
        self.maximumAnalysisUnitsPerRule = maximumAnalysisUnitsPerRule
        self.maximumDataClumpComparisons = maximumDataClumpComparisons
        self.maximumDetectionsPerRule = maximumDetectionsPerRule
    }

    private static func validate(
        minimumDataClumpElements: Int,
        minimumDataClumpOccurrences: Int,
        minimumRepeatedSwitchOccurrences: Int,
        maximumSourceFiles: Int,
        maximumTotalSourceBytes: Int,
        maximumAnalysisUnitsPerRule: Int,
        maximumDataClumpComparisons: Int,
        maximumDetectionsPerRule: Int
    ) throws {
        guard minimumDataClumpElements >= 3 else {
            throw RepositoryEvidenceContractError.invalidConfiguration(
                "minimumDataClumpElements must be at least 3"
            )
        }
        guard minimumDataClumpOccurrences >= 2, minimumRepeatedSwitchOccurrences >= 2 else {
            throw RepositoryEvidenceContractError.invalidConfiguration(
                "repository smell occurrence thresholds must be at least 2"
            )
        }
        guard maximumSourceFiles > 0, maximumTotalSourceBytes > 0,
            maximumAnalysisUnitsPerRule > 0, maximumDataClumpComparisons > 0,
            maximumDetectionsPerRule > 0
        else {
            throw RepositoryEvidenceContractError.invalidConfiguration(
                "repository analysis budgets must be positive"
            )
        }
    }
}

extension RepositoryAnalysisConfiguration {
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                minimumDataClumpElements: values.decode(Int.self, forKey: .minimumDataClumpElements),
                minimumDataClumpOccurrences: values.decode(Int.self, forKey: .minimumDataClumpOccurrences),
                minimumRepeatedSwitchOccurrences: values.decode(Int.self, forKey: .minimumRepeatedSwitchOccurrences),
                maximumSourceFiles: values.decode(Int.self, forKey: .maximumSourceFiles),
                maximumTotalSourceBytes: values.decode(Int.self, forKey: .maximumTotalSourceBytes),
                maximumAnalysisUnitsPerRule: values.decode(Int.self, forKey: .maximumAnalysisUnitsPerRule),
                maximumDataClumpComparisons: values.decode(Int.self, forKey: .maximumDataClumpComparisons),
                maximumDetectionsPerRule: values.decode(Int.self, forKey: .maximumDetectionsPerRule)
            )
        } catch let error as RepositoryEvidenceContractError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.description)
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case minimumDataClumpElements
        case minimumDataClumpOccurrences
        case minimumRepeatedSwitchOccurrences
        case maximumSourceFiles
        case maximumTotalSourceBytes
        case maximumAnalysisUnitsPerRule
        case maximumDataClumpComparisons
        case maximumDetectionsPerRule
    }
}
