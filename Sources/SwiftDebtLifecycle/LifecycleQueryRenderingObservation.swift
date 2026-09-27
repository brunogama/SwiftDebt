import Foundation

extension LifecycleReadService {
    func renderSourceObservation(_ source: SourceObservation) -> [String] {
        switch source.parseOutcome {
        case .parsed:
            return ["SourceUnit \(source.sourcePath.rawValue): parsed"]
        case .failed(let diagnostics):
            return ["SourceUnit \(source.sourcePath.rawValue): parse-failed"]
                + diagnostics.map {
                    "  \($0.location.file):\($0.location.line):\($0.location.column) "
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
            lines.append("  \(reason.code): \(reason.message)")
        }
        return lines
    }

    func renderDetection(_ detection: ObservedDetection) -> String {
        let location = detection.location
        return "Detection \(detection.id.rawValue) \(detection.rule.identity) "
            + "\(location.sourcePath.rawValue):\(location.line):\(location.column) "
            + "\(detection.severity.rawValue): \(detection.message)"
    }

    private func oneLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
