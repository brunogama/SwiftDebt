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

    @Test(arguments: [
        StrictConcurrencyFixture(
            name: "actor isolation",
            code: """
            actor Store {
              func scenario() {}
            }
            """,
            expected: .actorIsolation
        ),
        StrictConcurrencyFixture(
            name: "global actor",
            code: """
            @MainActor
            func scenario() {}
            """,
            expected: .globalActorIsolation
        ),
        StrictConcurrencyFixture(
            name: "sendable conformance",
            code: """
            struct Value: Sendable {
              let id: Int
            }
            """,
            expected: .sendableConformance
        ),
        StrictConcurrencyFixture(
            name: "unchecked sendable",
            code: """
            final class UnsafeBox: @unchecked Sendable {
              var value = 0
            }
            """,
            expected: .uncheckedSendable
        ),
        StrictConcurrencyFixture(
            name: "task creation",
            code: """
            func scenario() {
              Task { await refresh() }
              Task.detached { await refresh() }
            }
            """,
            expected: .unstructuredTask,
            expectedMinimumCount: 2
        ),
        StrictConcurrencyFixture(
            name: "nonisolated declaration",
            code: """
            actor Store {
              nonisolated func scenario() {}
            }
            """,
            expected: .nonisolatedDeclaration
        ),
        StrictConcurrencyFixture(
            name: "unsafe escape hatch",
            code: """
            func scenario(_ pointer: UnsafeRawPointer) {
              _ = pointer
            }
            """,
            expected: .unsafeEscapeHatch
        ),
    ])
    func strictConcurrencyFixtures(fixture: StrictConcurrencyFixture) throws {
        let result = parse(fixture.code)
        #expect(result.isValid, "fixture failed to parse: \(fixture.name)")
        let facts = result.riskFacts + result.functions.flatMap(\.riskFacts)

        let matchingFacts = facts.filter { $0.category == fixture.expected }
        #expect(matchingFacts.count >= fixture.expectedMinimumCount, "missing \(fixture.expected) for \(fixture.name)")
        #expect(facts.allSatisfy { !$0.detail.isEmpty })
        #expect(facts.allSatisfy { $0.confidence == .measuredSyntax || $0.confidence == .heuristic })
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

    @Test func apiAndConcurrencyRiskEvidenceExplainsHeuristicLimits() throws {
        let result = parse(
            """
            @MainActor
            public func scenario(
              _ a: Int,
              _ b: Int,
              _ c: Int,
              _ d: Int,
              _ e: Int,
              _ f: Int
            ) async {
              if a > b { await refresh() }
              Task.detached { await refresh() }
            }
            """)

        let evidence = DebtFunctionalEvidenceBuilder().evidence(for: [result])
        let concurrency = try #require(evidence.first { $0.kind == "swift.concurrency-risk.globalActorIsolation" })
        let parameterSurface = try #require(evidence.first { $0.kind == "swift.api-risk.parameter-surface" })
        let publicBoundary = try #require(evidence.first { $0.kind == "swift.api-risk.public-boundary-complexity" })

        #expect(concurrency.note?.contains("Heuristic SwiftSyntax risk evidence") == true)
        #expect(parameterSurface.note?.contains("Heuristic API surface risk") == true)
        #expect(publicBoundary.note?.contains("Heuristic public-boundary complexity") == true)
        #expect(evidence.allSatisfy { $0.note?.contains("not compiler semantic proof") == true })
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

    @Test func disabledSwiftSpecificRiskEvidenceIsDeterministic() throws {
        let parsed = parse(
            """
            @MainActor
            public func scenario(
              _ a: Int,
              _ b: Int,
              _ c: Int,
              _ d: Int,
              _ e: Int,
              _ f: Int
            ) async {
              Task { await refresh() }
              Task.detached { await refresh() }
            }
            """)
        let shuffled = ParsedSource(
            path: parsed.path,
            module: parsed.module,
            types: Array(parsed.types.reversed()),
            functions: Array(parsed.functions.reversed()),
            lines: parsed.lines,
            topLevelVariables: parsed.topLevelVariables,
            diagnostics: parsed.diagnostics,
            riskFacts: Array(parsed.riskFacts.reversed())
        )
        let builder = DebtFunctionalEvidenceBuilder(
            options: DebtFunctionalEvidenceOptions(includesSwiftSpecificRiskEvidence: false)
        )

        let originalEvidence = builder.evidence(for: [parsed])
        let shuffledEvidence = builder.evidence(for: [shuffled])
        let originalScore = DebtScoring().score(evidence: originalEvidence)
        let shuffledScore = DebtScoring().score(evidence: shuffledEvidence)

        #expect(originalEvidence == shuffledEvidence)
        #expect(originalScore == shuffledScore)
        #expect(originalEvidence.allSatisfy { !$0.kind.hasPrefix("swift.concurrency-risk.") })
        #expect(originalEvidence.allSatisfy { !$0.kind.hasPrefix("swift.api-risk.") })
    }

    struct StrictConcurrencyFixture: CustomTestStringConvertible {
        let name: String
        let code: String
        let expected: SwiftRiskCategory
        let expectedMinimumCount: Int

        init(name: String, code: String, expected: SwiftRiskCategory, expectedMinimumCount: Int = 1) {
            self.name = name
            self.code = code
            self.expected = expected
            self.expectedMinimumCount = expectedMinimumCount
        }

        var testDescription: String { name }
    }
}
