public enum RepositoryEvidenceContractError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidConfiguration(String)
    case invalidDigest(String)
    case emptyIssueCode
    case emptyIssueMessage
    case emptyRevision
    case inconsistentCapabilityState
    case unsupportedReportKind(String)
    case unsupportedSchemaVersion(Int)

    public var description: String {
        switch self {
        case .invalidConfiguration(let message): message
        case .invalidDigest(let value): "Invalid SHA-256 repository digest: \(value)"
        case .emptyIssueCode: "Repository evidence issue codes must be nonempty."
        case .emptyIssueMessage: "Repository evidence issue messages must be nonempty."
        case .emptyRevision: "Repository revision identifiers must be nonempty."
        case .inconsistentCapabilityState:
            "Available repository capabilities cannot have an issue, and all other states require one."
        case .unsupportedReportKind(let value): "Unsupported repository evidence report kind: \(value)"
        case .unsupportedSchemaVersion(let value): "Unsupported repository evidence schema version: \(value)"
        }
    }
}

public struct RepositoryDigest: Codable, Equatable, Hashable, Sendable {
    public let algorithm: String
    public let value: String

    package init(value: String) throws {
        guard value.utf8.count == 64,
            value.utf8.allSatisfy({ byte in
                switch byte {
                case 48...57, 97...102: true
                default: false
                }
            })
        else { throw RepositoryEvidenceContractError.invalidDigest(value) }
        algorithm = "sha256"
        self.value = value
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case value
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let algorithm = try values.decode(String.self, forKey: .algorithm)
        guard algorithm == "sha256" else {
            throw DecodingError.dataCorruptedError(
                forKey: .algorithm,
                in: values,
                debugDescription: "Repository evidence schema 1 supports only SHA-256 digests."
            )
        }
        do {
            try self.init(value: values.decode(String.self, forKey: .value))
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: values,
                debugDescription: "SHA-256 digests require 64 lowercase hexadecimal characters."
            )
        }
    }
}

public struct RepositoryEvidenceIssue: Codable, Equatable, Hashable, Sendable {
    public let code: String
    public let message: String

    package init(code: String, message: String) throws {
        guard hasRepositoryEvidenceContent(code) else {
            throw RepositoryEvidenceContractError.emptyIssueCode
        }
        guard hasRepositoryEvidenceContent(message) else {
            throw RepositoryEvidenceContractError.emptyIssueMessage
        }
        self.code = code
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                code: values.decode(String.self, forKey: .code),
                message: values.decode(String.self, forKey: .message)
            )
        } catch let error as RepositoryEvidenceContractError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.description)
            )
        }
    }
}

public enum RepositoryWorkingTreeState: String, Codable, Sendable {
    case clean
    case modified
}

public struct RepositoryVersionControlIdentity: Codable, Equatable, Sendable {
    public let revision: String
    public let workingTreeState: RepositoryWorkingTreeState

    public init(revision: String, workingTreeState: RepositoryWorkingTreeState) throws {
        guard hasRepositoryEvidenceContent(revision) else {
            throw RepositoryEvidenceContractError.emptyRevision
        }
        self.revision = revision
        self.workingTreeState = workingTreeState
    }

    private enum CodingKeys: String, CodingKey {
        case revision
        case workingTreeState
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                revision: values.decode(String.self, forKey: .revision),
                workingTreeState: values.decode(RepositoryWorkingTreeState.self, forKey: .workingTreeState)
            )
        } catch let error as RepositoryEvidenceContractError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.description)
            )
        }
    }
}

func hasRepositoryEvidenceContent(_ value: String) -> Bool {
    value.contains { !$0.isWhitespace }
        && !value.unicodeScalars.contains { $0.value < 32 || $0.value == 127 }
}

public struct RepositoryProviderIdentity: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let version: String

    package init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

public enum RepositoryCapabilityState: String, Codable, Sendable {
    case available
    case unavailable
    case ambiguous
    case failed
    case approximate
}

public struct RepositoryCapabilityEvidence: Codable, Equatable, Sendable {
    public let capability: String
    public let state: RepositoryCapabilityState
    public let provider: RepositoryProviderIdentity
    public let issue: RepositoryEvidenceIssue?

    package init(
        capability: String,
        state: RepositoryCapabilityState,
        provider: RepositoryProviderIdentity,
        issue: RepositoryEvidenceIssue? = nil
    ) throws {
        guard (state == .available) == (issue == nil) else {
            throw RepositoryEvidenceContractError.inconsistentCapabilityState
        }
        self.capability = capability
        self.state = state
        self.provider = provider
        self.issue = issue
    }

    private enum CodingKeys: String, CodingKey {
        case capability
        case state
        case provider
        case issue
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                capability: values.decode(String.self, forKey: .capability),
                state: values.decode(RepositoryCapabilityState.self, forKey: .state),
                provider: values.decode(RepositoryProviderIdentity.self, forKey: .provider),
                issue: values.decodeIfPresent(RepositoryEvidenceIssue.self, forKey: .issue)
            )
        } catch let error as RepositoryEvidenceContractError {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: error.description)
            )
        }
    }
}
