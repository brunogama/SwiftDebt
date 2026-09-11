import Testing

@testable import SCMACore
@testable import SCMASyntax

@Suite("SwiftSyntax extraction")
struct ParserTests {
    private func parse(_ code: String) -> ParsedSource {
        SwiftSyntaxParser().parse(SourceUnit(path: "Input.swift", content: code))
    }

    @Test func classesPropertiesAndMethods() {
        let result = parse(
            """
            // ignored
            class Counter {
                var value = 0
                let limit = 10
                func add(_ n: Int) {
                    if n > 0 { value += n }
                }
            }
            """)
        #expect(result.isValid)
        #expect(result.lines.count == 7)
        #expect(result.types.first?.propertyNames == ["value", "limit"])
        #expect(result.functions.first?.complexity == 2)
        #expect(result.functions.first?.codeLines == 1)
        #expect(result.functions.first?.parameters == 1)
        #expect(result.functions.first?.bareReferences.contains("value") == true)
    }
    @Test func commentsAreNotCodeButCommentMarkersInStringsAre() {
        let result = parse(
            """
            /* comment
               /* nested */
            */
            class C { // a comment
              let url = "https://example.test/*literal*/"
              // ignore
            }
            """)
        #expect(result.lines.map(\.number) == [4, 5, 7])
        #expect(result.types.first?.codeLines == 3)
    }
    @Test func unicodeAndCRLFLocations() {
        let result = parse("// 😀\r\nclass Café {\r\n  func café() {}\r\n}\r\n")
        #expect(result.functions.first?.location.line == 3)
        #expect(result.functions.first?.location.column == 3)
        #expect(result.lines.count == 3)
    }
    @Test func multilineLiteralCountsNonblankPhysicalLines() {
        let result = parse(
            #"""
            class C {
              let text = """
              one

              // this is literal text
              """
            }
            """#)
        #expect(result.isValid)
        #expect(result.lines.count == 6)
    }
    @Test func nestedCallablesHaveSeparateComplexity() {
        let result = parse(
            """
            class C {
              func outer(_ x: Bool) {
                func local() { if x {} }
                let block = { if x {} }
                if x {}
                _ = block
                local()
              }
            }
            """)
        #expect(result.functions.count == 2)
        #expect(result.functions[0].complexity == 2)
        #expect(result.functions[1].complexity == 2)
        #expect(result.functions[1].owner == nil)
    }
    @Test(arguments: [
        ("if flag {}", 2), ("guard flag else { return }", 2),
        ("while flag {}", 2), ("repeat {} while flag", 2),
        ("for n in [1] { _ = n }", 2), ("_ = flag ? 1 : 0", 2),
        ("if flag && flag || flag {}", 4),
        ("switch 1 { case 1, 2: break; case 3: break; default: break }", 3),
        ("do { try foo() } catch { }", 2),
        ("_ = optional ?? 0", 1),
    ])
    func decisionPolicy(code: String, complexity: Int) {
        let result = parse("func test() { \(code) }")
        #expect(result.isValid)
        #expect(result.functions.first?.complexity == complexity)
    }
    @Test func selfReferencesAndShadowing() {
        let result = parse("class C { var x = 0; func f(x: Int) { let y = x; self.x = y; object.x = 3 } }")
        #expect(result.functions.first?.explicitSelfReferences == ["x"])
        #expect(result.functions.first?.shadowedNames == ["x", "y"])
        #expect(result.functions.first?.bareReferences.isDisjoint(with: ["x", "y"]) == true)
    }
    @Test func conditionalCompilationConditionsAreNotDecisions() {
        let result = parse("func test() {\n#if DEBUG && os(iOS)\nprint(1)\n#else\nif flag {}\n#endif\n}")
        #expect(result.functions.first?.complexity == 2)
    }
    @Test func tupleBindingsAndStaticComputedProperties() {
        let result = parse(
            "class C { var (a, b) = (1, 2); static let x = 0; var value: Int { a }; func f() { let local = 1 } }")
        #expect(result.types.first?.propertyNames == ["a", "b", "x", "value"])
    }
    @Test func initializersAndDeinitializers() {
        let result = parse("class C { init(_ n: Int) {} ; deinit {} }")
        #expect(result.functions.count == 2)
        #expect(result.functions.map(\.parameters) == [1, 0])
        #expect(result.functions.allSatisfy { $0.complexity == 1 })
    }
    @Test func freeVariablesAreSeparate() {
        let result = parse("let global = 1; class C { let property = 2; func f() { let local = 3 } }")
        #expect(result.topLevelVariables == 1)
        #expect(result.types.first?.propertyNames == ["property"])
    }
    @Test func invalidSyntaxNeverProducesRecoveredMetrics() {
        let result = parse("class Broken { func f( {")
        #expect(!result.isValid)
        #expect(result.types.isEmpty)
        #expect(result.functions.isEmpty)
        #expect(!result.diagnostics.isEmpty)
    }
    @Test func importedModulesAndQualifiedReferences() {
        let result = parse("import Models\nclass C { var x: Models.Item?; func f() { _ = Models.Item() } }")
        #expect(result.types.first?.importedModules == ["Models"])
        #expect(result.types.first?.referencedTypes.contains("Models.Item") == true)
    }
    @Test func extensionsKeepOwnerAndFragments() {
        let result = parse("class C {}\nextension C { func f() {} }")
        #expect(result.types.count == 2)
        #expect(result.types[1].isExtension)
        #expect(result.functions.first?.owner == result.types.first?.key)
    }
    @Test func nestedTypeOwnersAreQualified() {
        let result = parse("class Outer { class Inner { func f() {} } }")
        #expect(result.types.map { $0.key.name } == ["Outer", "Outer.Inner"])
        #expect(result.functions.first?.owner?.name == "Outer.Inner")
    }
}
