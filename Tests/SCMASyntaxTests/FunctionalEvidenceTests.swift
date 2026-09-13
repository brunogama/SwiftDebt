import Testing

@testable import SCMACore
@testable import SCMASyntax

@Suite("Swift functional and side-effect evidence")
struct FunctionalEvidenceTests {
    private func parse(_ code: String) -> ParsedSource {
        SwiftSyntaxParser().parse(SourceUnit(path: "Input.swift", content: code))
    }

    @Test(arguments: [
        (
            "mutation",
            """
            func scenario() {
              var local = 0
              local += 1
            }
            """,
            SyntaxEffectCategory.mutation
        ),
        (
            "inout",
            """
            func scenario(_ value: inout Int) {
              value += 1
            }
            """,
            SyntaxEffectCategory.inoutMutation
        ),
        (
            "property write",
            """
            final class Box {
              var value = 0
              func scenario() {
                self.value = 1
              }
            }
            """,
            SyntaxEffectCategory.propertyWrite
        ),
        (
            "global state",
            """
            var global = 0
            func scenario() {
              global = 1
            }
            """,
            SyntaxEffectCategory.globalOrStaticState
        ),
        (
            "static state",
            """
            final class Box {
              static var shared = Box()
              func scenario() {
                Self.shared = Box()
              }
            }
            """,
            SyntaxEffectCategory.globalOrStaticState
        ),
        (
            "async",
            """
            func scenario(service: Service) async {
              await service.load()
            }
            """,
            SyntaxEffectCategory.asyncEffect
        ),
        (
            "throwing",
            """
            func scenario() throws {
              try save()
            }
            """,
            SyntaxEffectCategory.throwingEffect
        ),
        (
            "closure",
            """
            final class Box {
              var value = 0
              func scenario(_ values: [Int]) {
                values.map { item in self.value = item }
              }
            }
            """,
            SyntaxEffectCategory.closureEffect
        ),
    ])
    func sideEffectFixtures(name: String, code: String, category: SyntaxEffectCategory) throws {
        let result = parse(code)
        #expect(result.isValid, "fixture failed to parse: \(name)")
        let function = try #require(result.functions.first { $0.name.contains("scenario") })

        #expect(function.effectFacts.contains { $0.category == category }, "missing \(category) for \(name)")
        #expect(function.effectFacts.allSatisfy { !$0.detail.isEmpty })
        #expect(function.effectFacts.allSatisfy { $0.confidence == .measuredSyntax || $0.confidence == .heuristic })
    }

    @Test func knownBenignFunctionalCompositionDoesNotBecomeSideEffectEvidence() throws {
        let result = parse(
            """
            func scenario(_ values: [Int]) -> [Int] {
              values.map { $0 + 1 }.filter { $0 == 2 }
            }
            """)
        let function = try #require(result.functions.first)

        #expect(function.effectFacts.isEmpty)
        #expect(function.compositionFacts.map(\.operation).sorted() == ["filter", "map"])
        #expect(function.compositionFacts.allSatisfy { !$0.closureHasSideEffects })
    }

    @Test func heuristicEvidenceExplainsConfidenceAndSemanticLimits() throws {
        let result = parse(
            """
            func pure(_ values: [Int]) -> [Int] {
              values.map { $0 + 1 }
            }
            """)

        let evidence = DebtFunctionalEvidenceBuilder().evidence(for: [result])
        let purity = try #require(evidence.first { $0.kind == "swift.purity.heuristic" })
        let pattern = try #require(evidence.first { $0.kind == "swift.pattern-consistency.heuristic" })
        let composition = try #require(evidence.first { $0.kind == "swift.functional-composition" })

        #expect(purity.note?.contains("Heuristic inference") == true)
        #expect(pattern.note?.contains("Heuristic pattern-consistency") == true)
        #expect(composition.note?.contains("Measured functional call syntax") == true)
        #expect(evidence.allSatisfy { $0.note?.contains("not compiler semantic proof") == true })
    }

    @Test func scoringInputsAndExplanationsAreDeterministic() throws {
        let first = parse(
            """
            final class Box {
              var value = 0
              func mutate(_ values: [Int]) {
                values.map { item in self.value = item }
              }
              func pure(_ values: [Int]) -> [Int] {
                values.map { $0 + 1 }
              }
            }
            """)
        let shuffled = ParsedSource(
            path: first.path,
            module: first.module,
            types: first.types,
            functions: Array(first.functions.reversed()),
            lines: first.lines,
            topLevelVariables: first.topLevelVariables,
            diagnostics: first.diagnostics
        )

        let originalEvidence = DebtFunctionalEvidenceBuilder().evidence(for: [first])
        let shuffledEvidence = DebtFunctionalEvidenceBuilder().evidence(for: [shuffled])
        let originalScore = DebtScoring().score(evidence: originalEvidence)
        let shuffledScore = DebtScoring().score(evidence: shuffledEvidence)

        #expect(originalEvidence == shuffledEvidence)
        #expect(originalScore == shuffledScore)
        #expect(originalEvidence.map { "\($0.id)|\($0.rawValue)|\($0.note ?? "")" } == shuffledEvidence.map { "\($0.id)|\($0.rawValue)|\($0.note ?? "")" })
    }
}
