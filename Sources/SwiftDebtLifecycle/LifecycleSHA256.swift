import Foundation
import SwiftDebtCore

package enum LifecycleSHA256 {
    package static func hexDigest(_ data: Data) -> String {
        var hasher = RepositorySHA256()
        hasher.update(data)
        return hasher.finalizeHex()
    }
}

package struct LifecycleDigestInput {
    private var hasher = RepositorySHA256()

    package init() {}

    package mutating func append(_ value: String) {
        hasher.updateFramed(value)
    }

    package mutating func append(_ value: UInt64) {
        withUnsafeBytes(of: value.bigEndian) { bytes in
            hasher.update(bytes)
        }
    }

    package func hexDigest() -> String {
        var copy = hasher
        return copy.finalizeHex()
    }
}
