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

struct ForwardConfigurationCompatibilityRule: TestDebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "tests"),
        id: RuleID(validated: "forward-configuration-compatibility")
    )
    static let contract = RuleContract(
        semanticRevision: .initial,
        semantics: "Fixture with a future configuration compatibility source.",
        rationale: "Exercises the RuleEngine authority boundary.",
        configurationCompatibilityDeclarations: [futureConfigurationCompatibility]
    )

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws {}
}

struct UnbackedConfigurationCompatibilityRule: TestDebtRule {
    static let identity = RuleIdentity(
        namespace: RuleNamespace(validated: "tests"),
        id: RuleID(validated: "unbacked-configuration-compatibility")
    )
    static let contract = RuleContract(
        semanticRevision: secondRevision,
        semantics: "Fixture with configuration compatibility but no semantic declaration.",
        rationale: "Exercises cross-revision composition safety.",
        configurationCompatibilityDeclarations: [priorConfigurationCompatibility]
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

private let compatibilityEvidence: CompatibilityTestEvidence = {
    guard
        let evidence = CompatibilityTestEvidence(
            identifier: "RuleEngineTests.invalidConfigurationCompatibility",
            summary: "Exercises registration validation."
        )
    else {
        preconditionFailure("The test evidence is structurally valid.")
    }
    return evidence
}()

private let futureConfigurationCompatibility: ConfigurationCompatibilityDeclaration = {
    guard
        let declaration = ConfigurationCompatibilityDeclaration(
            fromRevision: secondRevision,
            supportedClaims: [.absence],
            conditions: [.maximumFileBytesNondecreasing],
            testEvidence: compatibilityEvidence,
            rationale: "Invalid because the containing rule is revision 1."
        )
    else {
        preconditionFailure("The declaration value is structurally valid.")
    }
    return declaration
}()

private let priorConfigurationCompatibility: ConfigurationCompatibilityDeclaration = {
    guard
        let declaration = ConfigurationCompatibilityDeclaration(
            fromRevision: .initial,
            supportedClaims: [.absence],
            conditions: [.maximumFileBytesNondecreasing],
            testEvidence: compatibilityEvidence,
            rationale: "Invalid because no semantic declaration covers the revision change."
        )
    else {
        preconditionFailure("The declaration value is structurally valid.")
    }
    return declaration
}()

private let secondRevision: SemanticRevision = {
    guard let revision = SemanticRevision(2) else {
        preconditionFailure("Two is a valid Semantic Revision.")
    }
    return revision
}()
