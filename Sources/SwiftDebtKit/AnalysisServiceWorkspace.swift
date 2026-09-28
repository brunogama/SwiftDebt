import Foundation
import SwiftDebtCore

struct PreparedAnalysis {
    let root: URL
    let configurationURL: URL
    let configuration: WorkspaceConfiguration
    let options: AnalysisOptions
    let selection: SourceDiscovery.Selection
    let sources: [SourceUnit]
}

extension AnalysisService {
    func prepare(_ request: AnalysisRequest, profiler: AnalysisProfiler?) throws
        -> PreparedAnalysis
    {
        profiler?.begin(.discovery)
        defer { profiler?.end(.discovery) }
        let discovery = SourceDiscovery()
        let root = try discovery.root(for: request)
        let configurationURL =
            request.configurationPath.map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent(".swift-debt.json")
        let configuration = try loadConfiguration(
            at: configurationURL, explicitlyRequested: request.configurationPath != nil)
        let options = try configuration.analysisOptions(overrides: request)
        let selection = try discovery.select(
            request: request, root: root, excludes: configuration.exclude + request.exclude)
        let sources = try discovery.read(
            selection,
            maximumFileBytes: request.maximumFileBytes ?? configuration.maximumFileBytes)
        return PreparedAnalysis(
            root: root, configurationURL: configurationURL, configuration: configuration,
            options: options, selection: selection, sources: sources)
    }

    private func loadConfiguration(at url: URL, explicitlyRequested: Bool) throws
        -> WorkspaceConfiguration
    {
        guard explicitlyRequested || FileManager.default.fileExists(atPath: url.path) else {
            return WorkspaceConfiguration()
        }
        do {
            return try JSONDecoder().decode(
                WorkspaceConfiguration.self, from: Data(contentsOf: url))
        } catch let failure as AnalysisFailure {
            throw AnalysisFailure.invalidConfiguration("\(url.path): \(failure)")
        } catch let failure as DecodingError {
            throw AnalysisFailure.invalidConfiguration(
                "\(url.path): \(decodingErrorDescription(failure))")
        } catch {
            throw WorkspaceError("Unable to read configuration \(url.path): \(error)")
        }
    }
}
