import Foundation
import SwiftDebtCore

public enum RepositorySyntaxCacheFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidStoragePath(String)
    case nonFileStorageURL
    case readFailed(String)
    case storageUnavailable
    case writeFailed(String)

    public var description: String {
        switch self {
        case .invalidStoragePath(let path):
            "Repository syntax cache path is not a regular file: \(path)"
        case .nonFileStorageURL:
            "Repository syntax cache storage must use a local file URL."
        case .readFailed(let path):
            "Unable to read repository syntax cache: \(path)"
        case .storageUnavailable:
            "The user cache directory is unavailable for repository syntax facts."
        case .writeFailed(let path):
            "Unable to atomically persist repository syntax cache: \(path)"
        }
    }
}

struct RepositorySyntaxCacheStore {
    enum LoadResult {
        case missing
        case corrupt
        case schemaMismatch
        case incompatible(reasons: [RepositorySyntaxCacheInvalidationReason])
        case compatible(document: RepositorySyntaxCacheDocument, data: Data)
    }

    struct PersistenceResult {
        let data: Data
        let digest: RepositoryDigest
        let writePerformed: Bool
    }

    static let retainedDataClasses = [
        "data-clump-syntax-facts",
        "fact-budget-dependencies",
        "parse-diagnostics",
        "repeated-switch-syntax-facts",
        "source-content-digests",
    ]

    func load(
        from url: URL,
        compatibility: RepositorySyntaxCacheCompatibility
    ) throws -> LoadResult {
        guard url.isFileURL, url.host == nil else {
            throw RepositorySyntaxCacheFailure.nonFileStorageURL
        }
        guard (url.path as NSString).isAbsolutePath else {
            throw RepositorySyntaxCacheFailure.invalidStoragePath(url.path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        guard !isDirectory.boolValue else {
            throw RepositorySyntaxCacheFailure.invalidStoragePath(url.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RepositorySyntaxCacheFailure.readFailed(url.path)
        }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(RepositorySyntaxCacheHeader.self, from: data),
            header.reportKind == RepositorySyntaxCacheDocument.reportKind
        else {
            return .corrupt
        }
        guard header.schemaVersion == RepositorySyntaxCacheDocument.schemaVersion else {
            return .schemaMismatch
        }
        guard let document = try? decoder.decode(RepositorySyntaxCacheDocument.self, from: data),
            (try? document.validate()) != nil,
            (try? encoded(document)) == data
        else {
            return .corrupt
        }
        let invalidationReasons = document.compatibility.invalidationReasons(
            comparedTo: compatibility
        )
        guard invalidationReasons.isEmpty else {
            return .incompatible(reasons: invalidationReasons)
        }
        return .compatible(document: document, data: data)
    }

    func persist(
        _ document: RepositorySyntaxCacheDocument,
        to url: URL,
        existingData: Data?,
        forceWrite: Bool
    ) throws -> PersistenceResult {
        guard url.isFileURL, url.host == nil else {
            throw RepositorySyntaxCacheFailure.nonFileStorageURL
        }
        guard (url.path as NSString).isAbsolutePath else {
            throw RepositorySyntaxCacheFailure.invalidStoragePath(url.path)
        }
        let data = try encoded(document)
        if !forceWrite, data == existingData {
            return try PersistenceResult(
                data: data,
                digest: digest(data),
                writePerformed: false
            )
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw RepositorySyntaxCacheFailure.invalidStoragePath(url.path)
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            guard try Data(contentsOf: url) == data else {
                throw RepositorySyntaxCacheFailure.writeFailed(url.path)
            }
        } catch let failure as RepositorySyntaxCacheFailure {
            throw failure
        } catch {
            throw RepositorySyntaxCacheFailure.writeFailed(url.path)
        }
        return try PersistenceResult(
            data: data,
            digest: digest(data),
            writePerformed: true
        )
    }

    func encoded(_ document: RepositorySyntaxCacheDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        data.append(0x0A)
        return data
    }

    func digest(_ data: Data) throws -> RepositoryDigest {
        var hasher = RepositorySHA256()
        hasher.update(data)
        return try RepositoryDigest(value: hasher.finalizeHex())
    }

    static func defaultURL(repositoryRoot: URL) throws -> URL {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw RepositorySyntaxCacheFailure.storageUnavailable
        }
        let identity = repositoryRoot.standardizedFileURL.resolvingSymlinksInPath().path
        var hasher = RepositorySHA256()
        hasher.updateFramed("swiftdebt-repository-syntax-cache-location-v1")
        hasher.updateFramed(identity)
        let digest = hasher.finalizeHex()
        return
            base
            .appendingPathComponent("SwiftDebt", isDirectory: true)
            .appendingPathComponent("repository-syntax", isDirectory: true)
            .appendingPathComponent("\(digest).json", isDirectory: false)
    }
}
