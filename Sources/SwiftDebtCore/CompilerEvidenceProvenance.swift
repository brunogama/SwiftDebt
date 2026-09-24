/// The compiler and toolchain that produced an evidence artifact.
public struct CompilerToolchainIdentity: Codable, Equatable, Sendable {
    public let compilerName: String
    public let compilerVersion: String
    public let compilerBuildIdentifier: String
    public let toolchainIdentifier: String

    public init(
        compilerName: String,
        compilerVersion: String,
        compilerBuildIdentifier: String,
        toolchainIdentifier: String
    ) {
        self.compilerName = compilerName
        self.compilerVersion = compilerVersion
        self.compilerBuildIdentifier = compilerBuildIdentifier
        self.toolchainIdentifier = toolchainIdentifier
    }
}

/// Build inputs that can change compiler-backed semantic results.
public struct CompilerBuildConfiguration: Codable, Equatable, Sendable {
    public let configurationName: String
    public let moduleName: String
    public let targetTriple: String
    public let sdkIdentifier: String?
    public let swiftLanguageVersion: String
    public let compilationConditions: [String]
    public let fingerprint: CompilerEvidenceDigest

    public init(
        configurationName: String,
        moduleName: String,
        targetTriple: String,
        sdkIdentifier: String? = nil,
        swiftLanguageVersion: String,
        compilationConditions: [String] = [],
        fingerprint: CompilerEvidenceDigest
    ) {
        self.configurationName = configurationName
        self.moduleName = moduleName
        self.targetTriple = targetTriple
        self.sdkIdentifier = sdkIdentifier
        self.swiftLanguageVersion = swiftLanguageVersion
        self.compilationConditions = Array(Set(compilationConditions)).sorted()
        self.fingerprint = fingerprint
    }
}

/// Provenance required to interpret a compiler-evidence report.
public struct CompilerEvidenceProvenance: Codable, Equatable, Sendable {
    public let analysisMode: CompilerEvidenceAnalysisMode
    public let generatorVersion: String
    public let compilerToolchain: CompilerToolchainIdentity
    public let buildConfiguration: CompilerBuildConfiguration
    public let sourceRevision: CompilerSourceRevision

    public init(
        generatorVersion: String,
        compilerToolchain: CompilerToolchainIdentity,
        buildConfiguration: CompilerBuildConfiguration,
        sourceRevision: CompilerSourceRevision
    ) {
        self.analysisMode = .compilerBacked
        self.generatorVersion = generatorVersion
        self.compilerToolchain = compilerToolchain
        self.buildConfiguration = buildConfiguration
        self.sourceRevision = sourceRevision
    }
}
