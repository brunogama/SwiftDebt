import Testing

@testable import SwiftDebtCore

@Suite("Rule observation value types")
struct RuleIdentityTests {
    @Test("Rule identity keeps namespace and ID distinct")
    func ruleIdentityComposition() throws {
        let namespace = try #require(RuleNamespace("com.example"))
        let id = try #require(RuleID("force-try"))
        let identity = RuleIdentity(namespace: namespace, id: id)

        #expect(identity.namespace == namespace)
        #expect(identity.id == id)
        #expect(identity.description == "com.example.force-try")
    }

    @Test("Invalid rule identifiers are recoverable")
    func invalidRuleIdentifiers() {
        #expect(RuleNamespace("") == nil)
        #expect(RuleNamespace("SwiftDebt") == nil)
        #expect(RuleNamespace("swiftdebt..rules") == nil)
        #expect(RuleID("") == nil)
        #expect(RuleID("ForceTry") == nil)
        #expect(RuleID("force_try") == nil)
    }

    @Test("Semantic revisions are positive and advance successively")
    func semanticRevisionSequence() throws {
        let second = try #require(SemanticRevision.initial.successor())
        let third = try #require(second.successor())
        let fourth = try #require(SemanticRevision(4))
        let maximum = try #require(SemanticRevision(UInt.max))

        #expect(SemanticRevision(0) == nil)
        #expect(SemanticRevision.initial.rawValue == 1)
        #expect(second.rawValue == 2)
        #expect(third.immediatelySucceeds(second))
        #expect(!third.immediatelySucceeds(.initial))
        #expect(third < fourth)
        #expect(third.description == "3")
        #expect(maximum.successor() == nil)
    }

    @Test("Rule contract owns revision and semantics separately from metadata")
    func ruleContractAndMetadata() throws {
        let identity = RuleIdentity(
            namespace: try #require(RuleNamespace("swiftdebt")),
            id: try #require(RuleID("force-try"))
        )
        let metadata = RuleMetadata(
            name: "Force try",
            defaultSeverity: .warning,
            remediation: "Handle the error."
        )
        let contract = RuleContract(
            semanticRevision: .initial,
            semantics: "Reports try!.",
            rationale: "try! can trap."
        )
        let descriptor = RuleDescriptor(identity: identity, metadata: metadata, contract: contract)

        #expect(descriptor.identity == identity)
        #expect(descriptor.metadata == metadata)
        #expect(descriptor.contract == contract)
        #expect(descriptor.semanticRevision == .initial)
    }

    @Test("Source paths normalize safe relative components")
    func sourcePathNormalization() throws {
        let path = try SourcePath("./Sources//Feature/../Feature/Input.swift")
        let shortPath = try SourcePath("a")

        #expect(path.rawValue == "Sources/Feature/Input.swift")
        #expect(path.description == path.rawValue)
        #expect(shortPath.rawValue == "a")
    }

    @Test(
        "Source paths reject unsafe or nonportable forms",
        arguments: [
            ("", "SourcePath must contain at least one relative component."),
            (".", "SourcePath must contain at least one relative component."),
            ("/tmp/Input.swift", "SourcePath must be relative: /tmp/Input.swift"),
            ("../Input.swift", "SourcePath must not escape its root: ../Input.swift"),
            (
                "Sources/../../Input.swift",
                "SourcePath must not escape its root: Sources/../../Input.swift"
            ),
            ("Sources\\Input.swift", "SourcePath must use forward slashes: Sources\\Input.swift"),
            ("C:/Input.swift", "SourcePath must be relative: C:/Input.swift"),
            ("Sources/\nInput.swift", "SourcePath must not contain control characters."),
        ]
    )
    func sourcePathRejection(path: String, expectedDescription: String) {
        do {
            _ = try SourcePath(path)
            Issue.record("Expected SourcePathError for \(path)")
        } catch let error as SourcePathError {
            #expect(error.description == expectedDescription)
        } catch {
            Issue.record("Expected SourcePathError, got \(error)")
        }
    }
}
