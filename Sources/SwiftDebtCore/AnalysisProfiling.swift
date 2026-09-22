public enum AnalysisPhase: String, CaseIterable, Codable, Sendable {
    case discovery
    case parsing
    case structuralEvidence
    case graph
    case coverage
    case repositoryHistory
    case functionalEvidence
    case scoring
    case aggregation
    case rendering
}

package protocol AnalysisPhaseSink: Sendable {
    func begin(_ phase: AnalysisPhase)
    func end(_ phase: AnalysisPhase)
}
