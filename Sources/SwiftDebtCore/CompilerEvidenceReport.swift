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
}
