import SwiftDebtCore
import Testing

@testable import SwiftDebtSyntax

@Suite("Refactoring smell syntax signals")
struct RefactoringSmellRuleTests {
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
}
