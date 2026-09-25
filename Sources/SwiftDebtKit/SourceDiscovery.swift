import Foundation
import SwiftDebtCore

struct SourceManifest: Codable {
    let root: String
    let sources: [Entry]
    struct Entry: Codable {
        let path: String
        let module: String
    }
}

struct SourceDiscovery {
    struct Selection {
        let root: URL
        let entries: [SourceManifest.Entry]
        let kind: LifecycleSelectionKind
        let skippedSymbolicLinks: Bool
    }
    private let ignoredDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "Pods", "Carthage", "node_modules", ".swift-debt",
    ]

    func root(for request: AnalysisRequest) throws -> URL {
        if let path = request.manifestPath {
            let manifest = try JSONDecoder().decode(
                SourceManifest.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            return URL(fileURLWithPath: manifest.root).standardizedFileURL.resolvingSymlinksInPath()
        }
        let path = URL(fileURLWithPath: request.path).standardizedFileURL.resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &directory) else {
            throw WorkspaceError("Input does not exist: \(request.path)")
        }
        return directory.boolValue ? path : path.deletingLastPathComponent()
    }

    func select(request: AnalysisRequest, root: URL, excludes: [String]) throws -> Selection {
        if let manifestPath = request.manifestPath {
            let manifest = try JSONDecoder().decode(
                SourceManifest.self, from: Data(contentsOf: URL(fileURLWithPath: manifestPath)))
            let entries = try manifest.sources.filter { entry in
                let url = URL(fileURLWithPath: entry.path, relativeTo: root).standardizedFileURL
                    .resolvingSymlinksInPath()
                guard url.pathExtension == "swift", isWithin(url, root: root), !entry.module.isEmpty else {
                    throw WorkspaceError(
                        "Manifest entries must be Swift files inside root with a nonempty module: \(entry.path)")
                }
                return !isExcluded(relativePath(url, root: root), excludes: excludes)
            }.map { entry in
                SourceManifest.Entry(
                    path: URL(fileURLWithPath: entry.path, relativeTo: root).standardizedFileURL
                        .resolvingSymlinksInPath().path,
                    module: entry.module
                )
            }
            return Selection(
                root: root,
                entries: entries.sorted { $0.path < $1.path },
                kind: .manifest,
                skippedSymbolicLinks: false
            )
        }
        let input = URL(fileURLWithPath: request.path).standardizedFileURL
        let inputValues = try input.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard inputValues.isSymbolicLink != true else {
            throw WorkspaceError("Explicit symbolic-link inputs are not followed: \(input.path)")
        }
        if inputValues.isDirectory != true {
            guard input.pathExtension == "swift" else { throw WorkspaceError("Input file is not Swift: \(input.path)") }
            let entries =
                isExcluded(relativePath(input, root: root), excludes: excludes)
                ? [] : [SourceManifest.Entry(path: input.path, module: "Workspace")]
            return Selection(root: root, entries: entries, kind: .file, skippedSymbolicLinks: false)
        }
        var enumerationError: (any Error)?
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                }
            )
        else { throw WorkspaceError("Unable to enumerate \(root.path)") }
        var entries: [SourceManifest.Entry] = []
        var skippedSymbolicLinks = false
        let stampPath = request.stampPath.map {
            canonicalPath(URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath())
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                skippedSymbolicLinks = true
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true && ignoredDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if isExcluded(relativePath(url, root: root), excludes: excludes) {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true, url.pathExtension == "swift", url.lastPathComponent != "Package.swift"
            else { continue }
            if let stampPath, canonicalPath(url) == stampPath { continue }
            entries.append(SourceManifest.Entry(path: url.path, module: "Workspace"))
        }
        if let enumerationError { throw enumerationError }
        return Selection(
            root: root,
            entries: entries.sorted { $0.path < $1.path },
            kind: .directory,
            skippedSymbolicLinks: skippedSymbolicLinks
        )
    }

    func read(_ selection: Selection, maximumFileBytes: Int) throws -> [SourceUnit] {
        try selection.entries.map { entry in
            let url = URL(fileURLWithPath: entry.path)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                throw WorkspaceError("Input is not a regular file: \(entry.path)")
            }
            guard (values.fileSize ?? 0) <= maximumFileBytes else {
                throw WorkspaceError("File exceeds maximumFileBytes: \(entry.path)")
            }
            let data = try Data(contentsOf: url)
            guard data.count <= maximumFileBytes else {
                throw WorkspaceError("File exceeds maximumFileBytes: \(entry.path)")
            }
            guard let content = String(data: data, encoding: .utf8) else {
                throw WorkspaceError("Input is not valid UTF-8: \(entry.path)")
            }
            return SourceUnit(path: relativePath(url, root: selection.root), module: entry.module, content: content)
        }
    }

    private func isExcluded(_ path: String, excludes: [String]) -> Bool {
        excludes.contains { prefix in
            let normalized = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
            return path == normalized || path.hasPrefix(normalized + "/")
        }
    }
}

/// Canonical path for prefix comparison. Darwin's `resolvingSymlinksInPath` strips the
/// `/private` prefix from `/private/var`, `/private/tmp`, and `/private/etc`, while directory
/// enumeration can hand back the unstripped spelling; canonicalizing both sides keeps
/// exclusions and relative report paths working under those roots.
private func canonicalPath(_ url: URL) -> String {
    url.standardizedFileURL.resolvingSymlinksInPath().path
}

func isWithin(_ url: URL, root: URL) -> Bool {
    let root = canonicalPath(root)
    let path = canonicalPath(url)
    let prefix = root == "/" ? "/" : root + "/"
    return path == root || path.hasPrefix(prefix)
}

func relativePath(_ url: URL, root: URL) -> String {
    let root = canonicalPath(root)
    let path = canonicalPath(url)
    let prefix = root == "/" ? "/" : root + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
}

struct WorkspaceError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
