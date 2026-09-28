import Foundation
import Testing

@testable import SwiftDebtCore
@testable import SwiftDebtSyntax

@Suite("swiftui.observed-object-owned-by-view")
struct ObservedObjectOwnedByViewRuleTests {
    private func fixture(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = root.appendingPathComponent("Fixtures/ObservedObjectOwnedByView/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func firesWhenObservedObjectIsInitializedInPlace() throws {
        let content = try fixture("InPlaceInitialization.swift.txt")
        let source = SourceUnit(path: "ProfileView.swift", content: content)

        let result = ObservedObjectOwnedByViewRule.detect(in: source)

        #expect(result.state == .complete)
        #expect(result.findings.count == 1)
        #expect(result.findings.first?.viewName == "ProfileView")
        #expect(result.findings.first?.propertyName == "vm")
    }

    @Test func doesNotFireWhenObservedObjectIsPassedInViaInit() throws {
        let content = try fixture("PassedInViaInit.swift.txt")
        let source = SourceUnit(path: "ProfileView.swift", content: content)

        let result = ObservedObjectOwnedByViewRule.detect(in: source)

        #expect(result.state == .complete)
        #expect(result.findings.isEmpty)
    }

    @Test func definitionMatchesCatalogIdentity() {
        #expect(
            ObservedObjectOwnedByViewRule.definition.identity.rawValue
                == "swiftui.observed-object-owned-by-view")
        #expect(ObservedObjectOwnedByViewRule.definition.scope == .sourceUnit)
        #expect(ObservedObjectOwnedByViewRule.definition.mode == .deterministic)
    }
}
