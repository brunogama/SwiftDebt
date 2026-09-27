import Foundation
import SwiftDebtLifecycle

struct GitBlamePorcelainParser {
    func parse(_ output: String, expectedSource: String) throws -> [GitRevisionID] {
        let expectedLines = sourceLines(expectedSource)
        if expectedLines.isEmpty {
            guard output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GitBlameEvidenceError.malformedOutput
            }
            return []
        }

        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var revisions: [GitRevisionID] = []
        var index = 0
        while revisions.count < expectedLines.count {
            guard index < lines.count,
                let header = try parseHeader(lines[index], expectedFinalLine: revisions.count + 1)
            else {
                throw GitBlameEvidenceError.malformedOutput
            }
            index += 1

            var content: String?
            while index < lines.count {
                let line = lines[index]
                index += 1
                if line.hasPrefix("\t") {
                    content = String(line.dropFirst())
                    break
                }
                guard !looksLikeHeader(line) else {
                    throw GitBlameEvidenceError.malformedOutput
                }
            }
            guard content == expectedLines[revisions.count] else {
                throw GitBlameEvidenceError.malformedOutput
            }
            revisions.append(header)
        }

        guard lines[index...].allSatisfy({ $0.isEmpty }) else {
            throw GitBlameEvidenceError.malformedOutput
        }
        return revisions
    }

    private func parseHeader(
        _ line: String,
        expectedFinalLine: Int
    ) throws -> GitRevisionID? {
        let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard fields.count == 3 || fields.count == 4,
            Int(fields[1]).map({ $0 > 0 }) == true,
            Int(fields[2]) == expectedFinalLine,
            fields.count == 3 || Int(fields[3]).map({ $0 > 0 }) == true
        else {
            return nil
        }
        return try GitRevisionID(fields[0])
    }

    private func looksLikeHeader(_ line: String) -> Bool {
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        guard fields.count == 3 || fields.count == 4 else { return false }
        return fields[0].count == 40 || fields[0].count == 64
    }
}
