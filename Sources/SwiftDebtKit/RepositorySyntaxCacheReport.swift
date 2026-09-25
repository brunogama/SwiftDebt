import Foundation
import SwiftDebtCore

public enum RepositorySyntaxCacheMode: String, Codable, Equatable, Sendable {
    case reuse
    case rebuild
    case disabled
}

public enum RepositorySyntaxCachePolicy: Sendable {
    case reuse(URL)
    case rebuild(URL)
    case disabled

    var storageURL: URL? {
        switch self {
        case .reuse(let url), .rebuild(let url): url
        case .disabled: nil
        }
    }
}

public enum RepositorySyntaxCacheDisposition: String, Codable, Sendable {
    case disabled
    case coldRebuild = "cold-rebuild"
    case warmReuse = "warm-reuse"
    case partialRebuild = "partial-rebuild"
    case forcedRebuild = "forced-rebuild"
    case recoveredCorruption = "recovered-corruption"
    case incompatibleRebuild = "incompatible-rebuild"
}

public enum RepositorySyntaxCacheInvalidationReason: String, Codable, Sendable {
    case cacheDisabled = "cache-disabled"
    case cacheMissing = "cache-missing"
    case forcedRebuild = "forced-rebuild"
    case cacheCorrupt = "cache-corrupt"
    case schemaMismatch = "schema-mismatch"
    case factSchemaMismatch = "fact-schema-mismatch"
    case projectionChanged = "projection-changed"
    case providerChanged = "provider-changed"
    case ruleSemanticsChanged = "rule-semantics-changed"
    case configurationChanged = "configuration-changed"
    case sourceAdded = "source-added"
    case sourceContentChanged = "source-content-changed"
    case sourceMetadataChanged = "source-metadata-changed"
    case dependencyChanged = "dependency-changed"
    case sourceRemoved = "source-removed"
}

public struct RepositorySyntaxCacheInvalidation: Codable, Equatable, Sendable {
    public let reason: RepositorySyntaxCacheInvalidationReason
    public let sourceCount: Int

    package init(reason: RepositorySyntaxCacheInvalidationReason, sourceCount: Int) {
        self.reason = reason
        self.sourceCount = sourceCount
    }
}

public struct RepositorySyntaxCacheRuleIdentity: Codable, Equatable, Sendable {
    public let ruleIdentity: String
    public let semanticRevision: UInt

    package init(ruleIdentity: String, semanticRevision: UInt) {
        self.ruleIdentity = ruleIdentity
        self.semanticRevision = semanticRevision
    }
}

public struct RepositorySyntaxCacheProviderIdentity: Codable, Equatable, Sendable {
    public let name: String
    public let packageVersion: String
    public let sourceRevision: String

    package init(name: String, packageVersion: String, sourceRevision: String) {
        self.name = name
        self.packageVersion = packageVersion
        self.sourceRevision = sourceRevision
    }
}

public struct RepositorySyntaxCacheCompatibility: Codable, Equatable, Sendable {
    public let cacheSchemaVersion: Int
    public let factSchemaVersion: Int
    public let projectionRevision: String
    public let provider: RepositorySyntaxCacheProviderIdentity
    public let rules: [RepositorySyntaxCacheRuleIdentity]
    public let maximumAnalysisUnitsPerRule: Int

    package init(
        cacheSchemaVersion: Int,
        factSchemaVersion: Int,
        projectionRevision: String,
        provider: RepositorySyntaxCacheProviderIdentity,
        rules: [RepositorySyntaxCacheRuleIdentity],
        maximumAnalysisUnitsPerRule: Int
    ) {
        self.cacheSchemaVersion = cacheSchemaVersion
        self.factSchemaVersion = factSchemaVersion
        self.projectionRevision = projectionRevision
        self.provider = provider
        self.rules = rules.sorted {
            if $0.ruleIdentity != $1.ruleIdentity { return $0.ruleIdentity < $1.ruleIdentity }
            return $0.semanticRevision < $1.semanticRevision
        }
        self.maximumAnalysisUnitsPerRule = maximumAnalysisUnitsPerRule
    }
}

public struct RepositorySyntaxCacheStorage: Codable, Equatable, Sendable {
    public let location: String?
    public let dataClasses: [String]
    public let byteCount: Int
    public let contentDigest: RepositoryDigest?
    public let writePerformed: Bool

    package init(
        location: String?,
        dataClasses: [String],
        byteCount: Int,
        contentDigest: RepositoryDigest?,
        writePerformed: Bool
    ) {
        self.location = location
        self.dataClasses = dataClasses.sorted()
        self.byteCount = byteCount
        self.contentDigest = contentDigest
        self.writePerformed = writePerformed
    }
}

public struct RepositorySyntaxCacheReport: Equatable, Sendable {
    public let reportKind: String
    public let schemaVersion: Int
    public let sourceSnapshotDigest: RepositoryDigest
    public let mode: RepositorySyntaxCacheMode
    public let disposition: RepositorySyntaxCacheDisposition
    public let compatibility: RepositorySyntaxCacheCompatibility
    public let storage: RepositorySyntaxCacheStorage
    public let selectedSourceCount: Int
    public let reusedSourceCount: Int
    public let recomputedSourceCount: Int
    public let removedSourceCount: Int
    public let invalidations: [RepositorySyntaxCacheInvalidation]
    public let networkRequestCount: Int

    package init(
        sourceSnapshotDigest: RepositoryDigest,
        mode: RepositorySyntaxCacheMode,
        disposition: RepositorySyntaxCacheDisposition,
        compatibility: RepositorySyntaxCacheCompatibility,
        storage: RepositorySyntaxCacheStorage,
        selectedSourceCount: Int,
        reusedSourceCount: Int,
        recomputedSourceCount: Int,
        removedSourceCount: Int,
        invalidations: [RepositorySyntaxCacheInvalidation]
    ) {
        self.reportKind = "swiftdebt-repository-syntax-cache"
        self.schemaVersion = 1
        self.sourceSnapshotDigest = sourceSnapshotDigest
        self.mode = mode
        self.disposition = disposition
        self.compatibility = compatibility
        self.storage = storage
        self.selectedSourceCount = selectedSourceCount
        self.reusedSourceCount = reusedSourceCount
        self.recomputedSourceCount = recomputedSourceCount
        self.removedSourceCount = removedSourceCount
        self.invalidations = invalidations.sorted { $0.reason.rawValue < $1.reason.rawValue }
        self.networkRequestCount = 0
    }
}

public struct RepositoryAnalysisResult: Sendable {
    public let evidenceReport: RepositoryEvidenceReport
    public let cacheReport: RepositorySyntaxCacheReport

    package init(evidenceReport: RepositoryEvidenceReport, cacheReport: RepositorySyntaxCacheReport) {
        self.evidenceReport = evidenceReport
        self.cacheReport = cacheReport
    }
}
