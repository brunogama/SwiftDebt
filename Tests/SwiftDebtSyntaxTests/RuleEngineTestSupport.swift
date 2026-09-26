import SwiftDebtCore
import SwiftParser
import Testing

@testable import SwiftDebtSyntax

func committedDetections(_ result: RuleAnalysisResult) throws -> [Detection] {
    guard case .committed(let detections) = result.outcome else {
        struct ExpectedCommitted: Error {}
        Issue.record("Expected committed, got \(result.outcome)")
        throw ExpectedCommitted()
    }
    return detections
}

protocol TestDebtRule: DebtRule {}

extension TestDebtRule {
    static var identity: RuleIdentity { ForceTryRule.identity }
    static var metadata: RuleMetadata { ForceTryRule.metadata }
    static var contract: RuleContract { ForceTryRule.contract }
}

final class InvocationRecorder {
    var invocations = 0
}

struct RecordingRule: TestDebtRule {
    let recorder: InvocationRecorder

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        recorder.invocations += 1
    }
}

struct UnsupportedAfterEmissionRule: TestDebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "tests"),
        id: RuleID(validated: "unsupported")
    )

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        emit(at: context.sourceFile, message: "Valid partial observation")
        throw UnsupportedRuleAnalysis(reason: "requires compiler facts")
    }
}

struct ThrowAfterEmissionRule: TestDebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "tests"),
        id: RuleID(validated: "throwing")
    )

    struct DeliberateFailure: Error, CustomStringConvertible {
        var description: String { "deliberate" }
    }

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        emit(at: context.sourceFile, message: "Valid partial observation")
        throw DeliberateFailure()
    }
}

struct InvalidThenUnsupportedRule: TestDebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "tests"),
        id: RuleID(validated: "invalid")
    )

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        emit(at: context.sourceFile, message: "Valid partial observation")
        emit(at: context.sourceFile, message: "invalid\nmessage")
        throw UnsupportedRuleAnalysis(reason: "requires compiler facts")
    }
}

struct ForeignNodeRule: TestDebtRule {
    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        let foreignTree = Parser.parse(source: "let foreign = 1")
        emit(at: foreignTree, message: "Foreign observation")
    }
}

final class EscapedEmission {
    var emit: (() -> Void)?
}

struct EscapingRule: TestDebtRule {
    let escape: EscapedEmission

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        escape.emit = {
            emit(at: context.sourceFile, message: "Late observation")
        }
    }
}

final class SourcePathRecorder {
    var path: SourcePath?
}

struct SourcePathRecordingRule: TestDebtRule {
    let recorder: SourcePathRecorder

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {
        recorder.path = context.sourcePath
    }
}

struct InvalidCompatibilityDirectionRule: TestDebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "tests"),
        id: RuleID(validated: "invalid-compatibility")
    )
    static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Fixture with a non-earlier compatibility source.",
        rationale: "Exercises the RuleEngine authority boundary.",
        compatibilityDeclarations: [sameRevisionCompatibility]
    )

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {}
}

private let sameRevisionCompatibility: SemanticCompatibilityDeclaration = {
    guard
        let declaration = SemanticCompatibilityDeclaration(
            fromRevision: .initial,
            supportedClaims: [.continuity],
            rationale: "Invalid because the containing rule is also revision 1."
        )
    else {
        preconditionFailure("The declaration value is structurally valid.")
    }
    return declaration
}()
