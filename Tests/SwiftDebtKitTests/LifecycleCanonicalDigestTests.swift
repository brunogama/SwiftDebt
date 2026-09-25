import Foundation
import SwiftDebtCore
import Testing

@testable import SwiftDebtKit

@Suite("Lifecycle canonical digests")
struct LifecycleCanonicalDigestTests {
    @Test("SHA-256 matches published vectors")
    func sha256Vectors() {
        #expect(
            LifecycleSHA256.hexDigest(Data())
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        #expect(
            LifecycleSHA256.hexDigest(Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("Source digest is order independent and binds path, module, and exact bytes")
    func sourceUnitDigest() throws {
        let first = SourceUnit(path: "Sources/A.swift", module: "Library", content: "let a = 1\n")
        let second = SourceUnit(path: "Sources/B.swift", module: "Library", content: "let b = 2\n")

        let digest = try LifecycleCanonicalDigest.sourceUnits([first, second])

        #expect(try LifecycleCanonicalDigest.sourceUnits([second, first]) == digest)
        #expect(
            try LifecycleCanonicalDigest.sourceUnits([
                SourceUnit(path: first.path, module: first.module, content: "let a = 3\n"), second,
            ]) != digest
        )
        #expect(
            try LifecycleCanonicalDigest.sourceUnits([
                SourceUnit(path: "Sources/Renamed.swift", module: first.module, content: first.content), second,
            ]) != digest
        )
        #expect(
            try LifecycleCanonicalDigest.sourceUnits([
                SourceUnit(path: first.path, module: "OtherModule", content: first.content), second,
            ]) != digest
        )
    }
}
