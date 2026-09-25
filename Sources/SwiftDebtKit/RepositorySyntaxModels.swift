import SwiftDebtCore

struct DataClumpElement: Hashable, Comparable, Sendable {
    let name: String
    let normalizedType: NormalizedTokenSequence

    static func < (lhs: DataClumpElement, rhs: DataClumpElement) -> Bool {
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.normalizedType < rhs.normalizedType
    }

    var displayValue: String { "\(name): \(normalizedType.displayValue)" }
    var fingerprintValue: String { "\(name):\(normalizedType.canonicalValue)" }
}

struct DataClumpUnit: Sendable {
    let kind: RepositoryAnalysisUnitKind
    let displayName: String
    let location: SwiftDebtCore.SourceLocation
    let elements: Set<DataClumpElement>

    var comparedUnit: RepositoryComparedUnit {
        RepositoryComparedUnit(kind: kind, displayName: displayName, location: location)
    }
}

struct RepeatedSwitchUnit: Sendable {
    let scope: String
    let discriminator: NormalizedTokenSequence
    let caseShape: [NormalizedTokenSequence]
    let displayName: String
    let location: SwiftDebtCore.SourceLocation

    var comparedUnit: RepositoryComparedUnit {
        RepositoryComparedUnit(kind: .switchStatement, displayName: displayName, location: location)
    }
}

struct RepositorySyntaxFacts: Sendable {
    var dataClumpUnits: [DataClumpUnit] = []
    var repeatedSwitchUnits: [RepeatedSwitchUnit] = []
    var conditionalSwitchLocations: [SwiftDebtCore.SourceLocation] = []
    var diagnostics: [AnalysisDiagnostic] = []
}

func sourceLocationOrder(
    _ lhs: SwiftDebtCore.SourceLocation,
    _ rhs: SwiftDebtCore.SourceLocation
) -> Bool {
    if lhs.file != rhs.file { return lhs.file < rhs.file }
    if lhs.line != rhs.line { return lhs.line < rhs.line }
    return lhs.column < rhs.column
}

func comparedUnitOrder(_ lhs: RepositoryComparedUnit, _ rhs: RepositoryComparedUnit) -> Bool {
    if sourceLocationOrder(lhs.location, rhs.location) { return true }
    if sourceLocationOrder(rhs.location, lhs.location) { return false }
    if lhs.kind.rawValue != rhs.kind.rawValue { return lhs.kind.rawValue < rhs.kind.rawValue }
    return lhs.displayName < rhs.displayName
}

func dataClumpUnitOrder(_ lhs: DataClumpUnit, _ rhs: DataClumpUnit) -> Bool {
    comparedUnitOrder(lhs.comparedUnit, rhs.comparedUnit)
}

func repeatedSwitchUnitOrder(_ lhs: RepeatedSwitchUnit, _ rhs: RepeatedSwitchUnit) -> Bool {
    comparedUnitOrder(lhs.comparedUnit, rhs.comparedUnit)
}

func diagnosticOrder(_ lhs: AnalysisDiagnostic, _ rhs: AnalysisDiagnostic) -> Bool {
    if sourceLocationOrder(lhs.location, rhs.location) { return true }
    if sourceLocationOrder(rhs.location, lhs.location) { return false }
    if lhs.severity.rawValue != rhs.severity.rawValue { return lhs.severity.rawValue < rhs.severity.rawValue }
    return lhs.message < rhs.message
}
