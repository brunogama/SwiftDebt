import Foundation

extension LifecycleReadService {
    func renderSourceObservation(_ source: SourceObservation) -> [String] {
        switch source.parseOutcome {
        case .parsed:
            return ["SourceUnit \(source.sourcePath.rawValue): parsed"]
        case .failed(let diagnostics):
            return ["SourceUnit \(source.sourcePath.rawValue): parse-failed"]
                + diagnostics.map {
                    "  \(oneLine($0.location.file)):\($0.location.line):\($0.location.column) "
                        + "\($0.severity.rawValue): \(oneLine($0.message))"
                }
        }
    }

    func renderAtomicObservation(_ observation: AtomicObservation) -> [String] {
        var lines = [
            "Atomic Observation \(observation.id.rawValue) "
                + "\(observation.rule.identity) \(observation.sourcePath.rawValue) "
                + observation.outcome.kind.rawValue
        ]
        switch observation.outcome {
        case .committed(let detectionIDs):
            lines.append("  Committed Detection IDs: \(detectionIDs.map(\.rawValue).joined(separator: ","))")
        case .unsupported(let reason), .failed(let reason), .excluded(let reason), .notExecuted(let reason):
            lines.append("  \(oneLine(reason.code)): \(oneLine(reason.message))")
        }
        return lines
    }

    func renderDetection(_ detection: ObservedDetection) -> String {
        let location = detection.location
        return "Detection \(detection.id.rawValue) \(detection.rule.identity) "
            + "\(location.sourcePath.rawValue):\(location.line):\(location.column) "
            + "\(detection.severity.rawValue): \(oneLine(detection.message))"
    }

    func renderAffectedFinding(_ id: FindingID) -> String {
        "Affected Finding \(oneLine(id.rawValue))"
    }

    func renderUnresolvedDetection(_ unresolved: UnresolvedDetection) -> [String] {
        let candidates = unresolved.candidateFindingIDs.map { oneLine($0.rawValue) }.joined(separator: ", ")
        return [
            "Unresolved Detection \(oneLine(unresolved.snapshotID.rawValue)) "
                + oneLine(unresolved.detectionID.rawValue),
            "  Candidate Findings: \(candidates)",
        ] + unresolved.reasons.map { "  \(oneLine($0.code)): \(oneLine($0.message))" }
    }

    private func oneLine(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 13: result += "\\r"
            case 92: result += "\\\\"
            case 0..<32, 127..<160, 0x2028, 0x2029:
                result += "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
            default:
                result.append(String(scalar))
            }
        }
        return result
    }
}
