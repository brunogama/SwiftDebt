import Foundation
import Testing

@testable import SwiftDebtCore
@testable import SwiftDebtSyntax

@Suite("architecture.global-shared-dependency detector")
struct GlobalSharedDependencyDetectorTests {
    private func fixture(_ name: String) throws -> SourceUnit {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = root.appendingPathComponent("Fixtures/\(name).swift.txt")
        let content = try String(contentsOf: url, encoding: .utf8)
        return SourceUnit(path: url.lastPathComponent, content: content)
    }

    @Test func mutableSingletonWithBroadUsageFires() throws {
        let source = try fixture("GlobalSharedDependencyMutableSingleton")
        let evidence = GlobalSharedDependencyDetector.detect(in: source)

        let match = try #require(evidence.first { $0.singletonTypeName == "SessionCache" })
        #expect(match.bindingName == "shared")
        #expect(match.hasMutableStoredProperty)
        #expect(match.mutablePropertyNames == ["lastUserID", "hitCount"])
        #expect(match.usageCount >= GlobalSharedDependencyDetector.usageThreshold)
        #expect(match.usageCount == 3)
        #expect(match.fires)
    }

    @Test func immutableUtilitySingletonWithBroadUsageNeverFires() throws {
        let source = try fixture("GlobalSharedDependencyImmutableUtility")
        let evidence = GlobalSharedDependencyDetector.detect(in: source)

        let match = try #require(evidence.first { $0.singletonTypeName == "NumberFormatterUtility" })
        #expect(match.bindingName == "shared")
        #expect(!match.hasMutableStoredProperty)
        #expect(match.mutablePropertyNames.isEmpty)
        // Usage is at least as high as the mutable-singleton fixture, to
        // prove the non-fire is about mutability, not the usage count
        // falling short of the threshold.
        #expect(match.usageCount >= GlobalSharedDependencyDetector.usageThreshold)
        #expect(!match.fires)
    }

    @Test func acceptsCommonSingletonNamingConventions() {
        #expect(GlobalSharedDependencyDetector.isSingletonBindingName("shared"))
        #expect(GlobalSharedDependencyDetector.isSingletonBindingName("default"))
        #expect(GlobalSharedDependencyDetector.isSingletonBindingName("instance"))
        #expect(GlobalSharedDependencyDetector.isSingletonBindingName("sharedInstance"))
        #expect(GlobalSharedDependencyDetector.isSingletonBindingName("sharedManager"))
        #expect(!GlobalSharedDependencyDetector.isSingletonBindingName("cache"))
        #expect(!GlobalSharedDependencyDetector.isSingletonBindingName("shared_instance"))
    }

    @Test func catalogEntryDeclaresTheExpectedShape() {
        let definition = GlobalSharedDependencyRule.definition
        #expect(definition.identity == RuleIdentity("architecture.global-shared-dependency"))
        #expect(definition.metadata.category == .architecture)
        #expect(definition.metadata.supportState == .partial)
        #expect(definition.mode == .heuristic)
        #expect(definition.scope == .sourceUnit)
        #expect(definition.metadata.provenance == [RuleProvenance(researchItem: 3, note: "addendum J")])
    }
}
