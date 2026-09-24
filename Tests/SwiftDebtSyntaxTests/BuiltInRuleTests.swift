import SwiftDebtCore
import Testing

@testable import SwiftDebtSyntax

@Suite("Built-in syntax debt rules")
struct BuiltInRuleTests {
    @Test("Unchecked Sendable reports only unchecked conformance syntax at the at sign")
    func uncheckedSendableBoundaries() throws {
        let source = SourceUnit(
            path: "Sources/Concurrency.swift",
            content: """
                final class Legacy: @unchecked Sendable {}
                struct Checked: Sendable {}
                #if FEATURE
                struct First: @unchecked Sendable {}
                #else
                struct Second: @unchecked Swift.Sendable {}
                #endif
                """
        )

        let result = try RuleEngine().analyze(source, using: UncheckedSendableRule())
        let detections = try committedDetections(result)

        #expect(detections.map(\.location.line) == [1, 4, 6])
        #expect(detections.map(\.location.column) == [21, 15, 16])
        #expect(detections.allSatisfy { $0.ruleIdentity == UncheckedSendableRule.identity })
        #expect(detections.allSatisfy { $0.severity == .information })
        #expect(
            detections.allSatisfy {
                $0.message
                    == "This @unchecked Sendable conformance disables compiler enforcement; review the type's thread-safety assumptions."
            }
        )
        #expect(UncheckedSendableRule.contract.semantics.contains("every #if branch"))
    }

    @Test("Actor isolation escape hatch reports direct members only at unsafe")
    func actorNonisolatedUnsafeBoundaries() throws {
        let source = SourceUnit(
            path: "Sources/Actor.swift",
            content: """
                actor Cache {
                  nonisolated(unsafe) static var count = 0
                  nonisolated func read() -> Int { 0 }
                  struct Nested {
                    nonisolated(unsafe) static var nested = 0
                  }
                #if FEATURE
                  nonisolated(unsafe) static var feature = 0
                #else
                  nonisolated(unsafe) static var fallback = 0
                #endif
                }
                extension Cache {
                  nonisolated(unsafe) static var extended: Int { 0 }
                }
                struct Plain {
                  nonisolated(unsafe) static var global = 0
                }
                """
        )

        let result = try RuleEngine().analyze(source, using: NonisolatedUnsafeActorMemberRule())
        let detections = try committedDetections(result)

        #expect(detections.map(\.location.line) == [2, 8, 10])
        #expect(detections.map(\.location.column) == [15, 15, 15])
        #expect(detections.allSatisfy { $0.ruleIdentity == NonisolatedUnsafeActorMemberRule.identity })
        #expect(detections.allSatisfy { $0.severity == .information })
        #expect(
            detections.allSatisfy {
                $0.message
                    == "This nonisolated(unsafe) actor member opts out of static isolation checking; review its synchronization assumptions."
            }
        )
        #expect(NonisolatedUnsafeActorMemberRule.contract.semantics.contains("Actor extensions are outside"))
        #expect(NonisolatedUnsafeActorMemberRule.contract.semantics.contains("every #if branch"))
    }

    @Test("Force cast reports only as! at the exclamation mark")
    func forceCastBoundaries() throws {
        let source = SourceUnit(
            path: "Sources/Casts.swift",
            content: """
                func convert(_ value: Any) {
                  _ = value as? String
                  _ = value as! String
                #if FEATURE
                  _ = value as! Int
                #else
                  _ = value as! Double
                #endif
                }
                """
        )

        let result = try RuleEngine().analyze(source, using: ForceCastRule())
        let detections = try committedDetections(result)

        #expect(detections.map(\.location.line) == [3, 5, 7])
        #expect(detections.map(\.location.column) == [15, 15, 15])
        #expect(detections.allSatisfy { $0.ruleIdentity == ForceCastRule.identity })
        #expect(detections.allSatisfy { $0.severity == .warning })
        #expect(
            detections.allSatisfy {
                $0.message
                    == "This forced cast traps if the value has a different runtime type; use a checked cast or explicit invariant."
            }
        )
        #expect(ForceCastRule.contract.semantics.contains("all #if branches"))
    }

    @Test("Empty catch reports empty and comment-only bodies at catch")
    func emptyCatchBoundaries() throws {
        let source = SourceUnit(
            path: "Sources/Catches.swift",
            content: """
                func load() {
                  do { try work() } catch {}
                  do { try work() } catch { /* intentionally ignored */ }
                  do { try work() } catch { print(error) }
                #if FEATURE
                  do { try work() } catch {}
                #else
                  do { try work() } catch { // ignored
                  }
                #endif
                }
                """
        )

        let result = try RuleEngine().analyze(source, using: EmptyCatchRule())
        let detections = try committedDetections(result)

        #expect(detections.map(\.location.line) == [2, 3, 6, 8])
        #expect(detections.map(\.location.column) == [21, 21, 21, 21])
        #expect(detections.allSatisfy { $0.ruleIdentity == EmptyCatchRule.identity })
        #expect(detections.allSatisfy { $0.severity == .warning })
        #expect(
            detections.allSatisfy {
                $0.message
                    == "This catch clause has an empty body and discards the error; handle or propagate it."
            }
        )
        #expect(EmptyCatchRule.contract.semantics.contains("comments and trivia do not count"))
        #expect(EmptyCatchRule.contract.semantics.contains("Every #if branch"))
    }

    @Test("Built-in catalog order and identities are stable")
    func catalogOrder() {
        #expect(
            BuiltInRuleCatalog.all.map { type(of: $0).identity.description } == [
                "swiftdebt.force-try",
                "swiftdebt.concurrency.unchecked-sendable",
                "swiftdebt.concurrency.actor-nonisolated-unsafe",
                "swiftdebt.code-smell.force-cast",
                "swiftdebt.code-smell.empty-catch",
            ]
        )
    }
}
