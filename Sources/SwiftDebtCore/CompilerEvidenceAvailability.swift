/// A stable reason that compiler evidence cannot be consumed as a semantic fact.
public struct CompilerEvidenceIssue: Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) throws {
        guard Self.hasContent(code) else {
            throw CompilerEvidenceContractError.emptyEvidenceIssueCode
        }
        guard Self.hasContent(message) else {
            throw CompilerEvidenceContractError.emptyEvidenceIssueMessage
        }
        self.code = code
        self.message = message
    }

    private static func hasContent(_ value: String) -> Bool {
        value.contains { !$0.isWhitespace }
    }
}

extension CompilerEvidenceIssue: Codable {
    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let code = try values.decode(String.self, forKey: .code)
        let message = try values.decode(String.self, forKey: .message)
        guard Self.hasContent(code) else {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: values,
                debugDescription: "A compiler-evidence issue code cannot be blank."
            )
        }
        guard Self.hasContent(message) else {
            throw DecodingError.dataCorruptedError(
                forKey: .message,
                in: values,
                debugDescription: "A compiler-evidence issue message cannot be blank."
            )
        }
        self.code = code
        self.message = message
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(code, forKey: .code)
        try values.encode(message, forKey: .message)
    }
}

/// Whether one compiler-backed capability produced usable, missing, or non-unique evidence.
public enum CompilerEvidenceAvailability: Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case available
        case unavailable
        case ambiguous
    }

    case available
    case unavailable(CompilerEvidenceIssue)
    case ambiguous(CompilerEvidenceIssue)

    public var state: State {
        switch self {
        case .available: .available
        case .unavailable: .unavailable
        case .ambiguous: .ambiguous
        }
    }

    public var issue: CompilerEvidenceIssue? {
        switch self {
        case .available: nil
        case .unavailable(let issue), .ambiguous(let issue): issue
        }
    }

    public var isAvailable: Bool {
        self == .available
    }
}

extension CompilerEvidenceAvailability: Codable {
    private enum CodingKeys: String, CodingKey {
        case state
        case issue
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let state = try values.decode(State.self, forKey: .state)
        switch state {
        case .available:
            guard !values.contains(.issue) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .issue,
                    in: values,
                    debugDescription: "Available compiler evidence cannot carry an issue."
                )
            }
            self = .available
        case .unavailable:
            self = .unavailable(try values.decode(CompilerEvidenceIssue.self, forKey: .issue))
        case .ambiguous:
            self = .ambiguous(try values.decode(CompilerEvidenceIssue.self, forKey: .issue))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(state, forKey: .state)
        if let issue {
            try values.encode(issue, forKey: .issue)
        }
    }
}
