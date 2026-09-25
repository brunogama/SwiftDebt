import SwiftDebtCore
import Testing

@testable import SwiftDebtSyntax

@Suite("Refactoring smell syntax signals")
struct RefactoringSmellRuleTests {
    @Test("Published catalog references the executable rule contracts")
    func catalogReferencesExecutableRules() throws {
        let rules: [(String, RuleIdentity, SemanticRevision)] = [
            ("Long Function", LongFunctionRule.identity, LongFunctionRule.contract.semanticRevision),
            ("Long Parameter List", LongParameterListRule.identity, LongParameterListRule.contract.semanticRevision),
            ("Global Data", GlobalDataRule.identity, GlobalDataRule.contract.semanticRevision),
            ("Large Class", LargeClassRule.identity, LargeClassRule.contract.semanticRevision),
        ]

        for (name, identity, revision) in rules {
            let entry = try #require(RefactoringCodeSmellCatalog.named(name))
            #expect(entry.ruleIdentity == identity.description)
            #expect(entry.semanticRevision == revision.rawValue)
        }
    }

    @Test("Long Function reports the threshold and preserves a clean shorter function")
    func longFunction() throws {
        let body = (1...20).map { "let value\($0) = \($0)" }.joined(separator: "\n")
        let source = SourceUnit(
            path: "Example.swift",
            content: "func lengthy() {\n\(body)\n}\nfunc short() { let value = 1 }"
        )
        let result = try RuleEngine().analyze(source, using: LongFunctionRule())

        #expect(result.isCommitted)
        #expect(result.detections.count == 1)
        #expect(result.detections.first?.location.line == 1)
        #expect(result.detections.first?.message.contains("20 top-level statements") == true)
    }

    @Test("Long Parameter List checks functions and initializers")
    func longParameterList() throws {
        let source = SourceUnit(
            path: "Example.swift",
            content: """
                func configure(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {}
                struct Small {
                    init(a: Int, b: Int, c: Int, d: Int, e: Int) {}
                }
                struct Large {
                    init(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {}
                }
                """
        )
        let result = try RuleEngine().analyze(source, using: LongParameterListRule())

        #expect(result.isCommitted)
        #expect(result.detections.map(\.location.line) == [1, 6])
        #expect(result.detections.allSatisfy { $0.message.contains("6 parameters") })
    }

    @Test("Global Data reports direct mutable file scope only")
    func globalData() throws {
        let source = SourceUnit(
            path: "Example.swift",
            content: """
                let stable = 1
                var mutable = 0
                #if FEATURE
                var conditional = 0
                #endif
                struct Store { var local = 0 }
                func update() { var local = 1; local += 1 }
                """
        )
        let result = try RuleEngine().analyze(source, using: GlobalDataRule())

        #expect(result.isCommitted)
        #expect(result.detections.map(\.location.line) == [2])
        #expect(result.detections.first?.location.column == 1)
    }

    @Test("Large Class reports direct members at threshold")
    func largeClass() throws {
        let members = (1...20).map { "var value\($0) = \($0)" }.joined(separator: "\n")
        let source = SourceUnit(
            path: "Example.swift",
            content: "class Large {\n\(members)\n}\nclass Small { var value = 0 }"
        )
        let result = try RuleEngine().analyze(source, using: LargeClassRule())

        #expect(result.isCommitted)
        #expect(result.detections.count == 1)
        #expect(result.detections.first?.message.contains("20 direct members") == true)
    }

    @Test("Statement and member counts are independent of physical lines")
    func countsDeclarationsRatherThanLines() throws {
        let statements = (1...20).map { "let value\($0) = \($0)" }.joined(separator: "; ")
        let members = (1...20).map { "var value\($0) = \($0)" }.joined(separator: "; ")
        let source = SourceUnit(
            path: "Example.swift",
            content: "func lengthy() { \(statements) }\nclass Large { \(members) }\nstruct AlsoLarge { \(members) }"
        )

        let functionResult = try RuleEngine().analyze(source, using: LongFunctionRule())
        let classResult = try RuleEngine().analyze(source, using: LargeClassRule())

        #expect(functionResult.isCommitted)
        #expect(classResult.isCommitted)
        #expect(functionResult.detections.map(\.location.line) == [1])
        #expect(classResult.detections.map(\.location.line) == [2])
    }
}
