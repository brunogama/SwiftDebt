/// The schema version for standalone compiler-evidence reports.
public enum CompilerEvidenceReportSchema {
    public static let currentVersion = 1
}

/// Analysis modes represented by the compiler-evidence sidecar.
public enum CompilerEvidenceAnalysisMode: String, Codable, Sendable {
    case compilerBacked = "compiler-backed"
}

/// Availability of every compiler-backed capability reserved by schema version 1.
public struct CompilerEvidenceAvailabilitySet: Codable, Equatable, Sendable {
    public let typeChecking: CompilerEvidenceAvailability
    public let conditionalCompilation: CompilerEvidenceAvailability
    public let macroExpansion: CompilerEvidenceAvailability
    public let nameBinding: CompilerEvidenceAvailability
    public let dispatchTargets: CompilerEvidenceAvailability

    public init(
        typeChecking: CompilerEvidenceAvailability,
        conditionalCompilation: CompilerEvidenceAvailability,
        macroExpansion: CompilerEvidenceAvailability,
        nameBinding: CompilerEvidenceAvailability,
        dispatchTargets: CompilerEvidenceAvailability
    ) {
        self.typeChecking = typeChecking
        self.conditionalCompilation = conditionalCompilation
        self.macroExpansion = macroExpansion
        self.nameBinding = nameBinding
        self.dispatchTargets = dispatchTargets
    }
}

/// A standalone, versioned record of compiler provenance and capability availability.
public struct CompilerEvidenceReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let reportKind: String
    public let generator: String
    public let provenance: CompilerEvidenceProvenance
    public let availability: CompilerEvidenceAvailabilitySet

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reportKind
        case generator
        case provenance
        case availability
    }

    public init(
        schemaVersion: Int = CompilerEvidenceReportSchema.currentVersion,
        reportKind: String = "swiftdebt-compiler-evidence",
        generator: String = "SwiftDebt",
        provenance: CompilerEvidenceProvenance,
        availability: CompilerEvidenceAvailabilitySet
    ) {
        self.schemaVersion = schemaVersion
        self.reportKind = reportKind
        self.generator = generator
        self.provenance = provenance
        self.availability = availability
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == CompilerEvidenceReportSchema.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: values,
                debugDescription: "Unsupported compiler evidence report schema version \(schemaVersion)"
            )
        }

        self.schemaVersion = schemaVersion
        self.reportKind = try values.decode(String.self, forKey: .reportKind)
        self.generator = try values.decode(String.self, forKey: .generator)
        self.provenance = try values.decode(CompilerEvidenceProvenance.self, forKey: .provenance)
        self.availability = try values.decode(CompilerEvidenceAvailabilitySet.self, forKey: .availability)
    }
}
