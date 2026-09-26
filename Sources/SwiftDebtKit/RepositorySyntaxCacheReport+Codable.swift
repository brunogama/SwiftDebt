import Foundation
import SwiftDebtCore

extension RepositorySyntaxCacheReport: Codable {
    private enum CodingKeys: String, CodingKey {
        case reportKind
        case schemaVersion
        case sourceSnapshotDigest
        case mode
        case disposition
        case compatibility
        case storage
        case selectedSourceCount
        case reusedSourceCount
        case recomputedSourceCount
        case removedSourceCount
        case invalidations
        case networkRequestCount
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let reportKind = try values.decode(String.self, forKey: .reportKind)
        let schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        let sourceSnapshotDigest = try values.decode(
            RepositoryDigest.self,
            forKey: .sourceSnapshotDigest
        )
        let mode = try values.decode(RepositorySyntaxCacheMode.self, forKey: .mode)
        let disposition = try values.decode(
            RepositorySyntaxCacheDisposition.self,
            forKey: .disposition
        )
        let compatibility = try values.decode(
            RepositorySyntaxCacheCompatibility.self,
            forKey: .compatibility
        )
        let storage = try values.decode(RepositorySyntaxCacheStorage.self, forKey: .storage)
        let selectedSourceCount = try values.decode(Int.self, forKey: .selectedSourceCount)
        let reusedSourceCount = try values.decode(Int.self, forKey: .reusedSourceCount)
        let recomputedSourceCount = try values.decode(Int.self, forKey: .recomputedSourceCount)
        let removedSourceCount = try values.decode(Int.self, forKey: .removedSourceCount)
        let invalidations = try values.decode(
            [RepositorySyntaxCacheInvalidation].self,
            forKey: .invalidations
        )
        let networkRequestCount = try values.decode(Int.self, forKey: .networkRequestCount)

        guard reportKind == "swiftdebt-repository-syntax-cache",
            schemaVersion == 1,
            cacheReportIsValid(
                mode: mode,
                disposition: disposition,
                compatibility: compatibility,
                storage: storage,
                selectedSourceCount: selectedSourceCount,
                reusedSourceCount: reusedSourceCount,
                recomputedSourceCount: recomputedSourceCount,
                removedSourceCount: removedSourceCount,
                invalidations: invalidations,
                networkRequestCount: networkRequestCount
            )
        else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Repository syntax cache report has inconsistent state or provenance."
                )
            )
        }

        self.init(
            sourceSnapshotDigest: sourceSnapshotDigest,
            mode: mode,
            disposition: disposition,
            compatibility: compatibility,
            storage: storage,
            selectedSourceCount: selectedSourceCount,
            reusedSourceCount: reusedSourceCount,
            recomputedSourceCount: recomputedSourceCount,
            removedSourceCount: removedSourceCount,
            invalidations: invalidations
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(reportKind, forKey: .reportKind)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(sourceSnapshotDigest, forKey: .sourceSnapshotDigest)
        try values.encode(mode, forKey: .mode)
        try values.encode(disposition, forKey: .disposition)
        try values.encode(compatibility, forKey: .compatibility)
        try values.encode(storage, forKey: .storage)
        try values.encode(selectedSourceCount, forKey: .selectedSourceCount)
        try values.encode(reusedSourceCount, forKey: .reusedSourceCount)
        try values.encode(recomputedSourceCount, forKey: .recomputedSourceCount)
        try values.encode(removedSourceCount, forKey: .removedSourceCount)
        try values.encode(invalidations, forKey: .invalidations)
        try values.encode(networkRequestCount, forKey: .networkRequestCount)
    }
}
