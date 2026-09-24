import SwiftDebtCore
import SwiftSyntax

public protocol DebtRule {
    static var identity: RuleIdentity { get }
    static var metadata: RuleMetadata { get }
    static var contract: RuleContract { get }

    func detect(in context: AnalysisContext, emit: DetectionEmitter) throws
}

public struct AnalysisContext {
    public let sourceFile: SourceFileSyntax
    public let sourcePath: SourcePath

    package init(sourceFile: SourceFileSyntax, sourcePath: SourcePath) {
        self.sourceFile = sourceFile
        self.sourcePath = sourcePath
    }
}

public struct DetectionEmitter {
    private let record: (Syntax, String) -> Void

    package init(record: @escaping (Syntax, String) -> Void) {
        self.record = record
    }

    public func callAsFunction<Node: SyntaxProtocol>(at node: Node, message: String) {
        record(Syntax(node), message)
    }
}

/// Throw this from a rule when its contract cannot run for the supplied source.
public struct UnsupportedRuleAnalysis: Error, Equatable, Sendable, CustomStringConvertible {
    public let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public var description: String { reason }
}
