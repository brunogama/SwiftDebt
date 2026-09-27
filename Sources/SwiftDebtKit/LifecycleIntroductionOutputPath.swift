import Foundation

package enum LifecycleIntroductionOutputPath {
    package static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    package static func hasSameIdentity(_ first: URL, _ second: URL) -> Bool {
        identity(first) == identity(second)
    }

    package static func contains(_ url: URL, within root: URL) -> Bool {
        let path = identity(url)
        let rootPath = identity(root)
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        return path == rootPath || path.hasPrefix(prefix)
    }

    private static func identity(_ url: URL) -> String {
        let resolved = canonical(url)
        #if os(macOS)
            if volumeUsesCaseInsensitiveNames(at: resolved) {
                return resolved.path.precomposedStringWithCanonicalMapping.lowercased(
                    with: Locale(identifier: "en_US_POSIX")
                )
            }
        #endif
        return resolved.path
    }

    #if os(macOS)
        private static func volumeUsesCaseInsensitiveNames(at url: URL) -> Bool {
            var existing = url
            while !FileManager.default.fileExists(atPath: existing.path) {
                let parent = existing.deletingLastPathComponent()
                guard parent.path != existing.path else { return false }
                existing = parent
            }
            let values = try? existing.resourceValues(
                forKeys: [.volumeSupportsCaseSensitiveNamesKey]
            )
            return values?.volumeSupportsCaseSensitiveNames == false
        }
    #endif
}
