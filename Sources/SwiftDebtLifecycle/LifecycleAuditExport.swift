import Foundation

extension LifecycleReadService {
    public func exportAudit(at url: URL) throws -> String {
        let store = LifecycleArtifactStore(artifactURL: url)
        return String(decoding: try store.canonicalData(for: store.load()), as: UTF8.self)
    }
}
