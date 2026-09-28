import Foundation
import SwiftDebtCore
import SwiftDebtKit

extension CLIOptions {
    func debtFormat(_ value: String?, validates: Bool) throws -> ReportFormat {
        guard let value else { return validates ? .debtCompact : .debtText }
        switch value {
        case "json", "debt-json": return .debtJSON
        case "markdown", "md", "debt-markdown": return .debtMarkdown
        case "dot", "debt-dot": return .debtDot
        case "text", "plain", "debt-text": return .debtText
        case "compact", "debt-compact": return .debtCompact
        case "debtmap-json": return .debtmapJSON
        default: throw CLIError("Invalid debt format: \(value)")
        }
    }

    func optionalRaw<T: RawRepresentable>(
        _ type: T.Type, _ value: String?, named name: String
    ) throws -> T?
    where T.RawValue == String {
        guard let value else { return nil }
        guard let decoded = T(rawValue: value) else { throw CLIError("Invalid \(name): \(value)") }
        return decoded
    }

    func optionalInteger(_ value: String?, named name: String, range: ClosedRange<Int>)
        throws -> Int?
    {
        guard let value else { return nil }
        guard let number = Int(value), range.contains(number) else {
            throw CLIError("Invalid integer for \(name): \(value)")
        }
        return number
    }

    func optionalScore(_ value: String?, named name: String) throws -> Double? {
        guard let value else { return nil }
        guard let score = Double(value), (0...100).contains(score) else {
            throw CLIError("Invalid score for \(name): \(value)")
        }
        return score
    }

    func setUnique(_ values: inout [String: String], key: String, value: String) throws {
        guard values[key] == nil else { throw CLIError("Duplicate option: \(key)") }
        values[key] = value
    }
}
