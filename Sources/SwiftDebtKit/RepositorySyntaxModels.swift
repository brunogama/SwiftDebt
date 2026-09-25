import SwiftDebtCore

struct DataClumpElement: Codable, Hashable, Comparable, Sendable {
    let name: String
    let normalizedType: NormalizedTokenSequence

    static func < (lhs: DataClumpElement, rhs: DataClumpElement) -> Bool {
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.normalizedType < rhs.normalizedType
    }

    var displayValue: String { "\(name): \(normalizedType.displayValue)" }
}

struct DataClumpUnit: Codable, Equatable, Sendable {
    let kind: RepositoryAnalysisUnitKind
    let displayName: String
    let location: SwiftDebtCore.SourceLocation
    let elements: Set<DataClumpElement>

    var comparedUnit: RepositoryComparedUnit {
        RepositoryComparedUnit(kind: kind, displayName: displayName, location: location)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, displayName, location, elements
    }

    init(
        kind: RepositoryAnalysisUnitKind,
        displayName: String,
        location: SwiftDebtCore.SourceLocation,
        elements: Set<DataClumpElement>
    ) {
        self.kind = kind
        self.displayName = displayName
        self.location = location
        self.elements = elements
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(RepositoryAnalysisUnitKind.self, forKey: .kind)
        displayName = try values.decode(String.self, forKey: .displayName)
        location = try values.decode(SwiftDebtCore.SourceLocation.self, forKey: .location)
        let decoded = try values.decode([DataClumpElement].self, forKey: .elements)
        guard Set(decoded).count == decoded.count, decoded == decoded.sorted() else {
            throw DecodingError.dataCorruptedError(
                forKey: .elements,
                in: values,
                debugDescription: "Data Clump elements must be unique and canonically ordered."
            )
        }
        elements = Set(decoded)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(displayName, forKey: .displayName)
        try values.encode(location, forKey: .location)
        try values.encode(elements.sorted(), forKey: .elements)
    }
}

struct RepeatedSwitchUnit: Codable, Equatable, Sendable {
    let scope: String
    let discriminator: NormalizedTokenSequence
    let caseShape: [NormalizedTokenSequence]
    let displayName: String
    let location: SwiftDebtCore.SourceLocation

    var comparedUnit: RepositoryComparedUnit {
        RepositoryComparedUnit(kind: .switchStatement, displayName: displayName, location: location)
    }
}

struct RepositorySyntaxFacts: Codable, Equatable, Sendable {
    var dataClumpUnits: [DataClumpUnit] = []
    var repeatedSwitchUnits: [RepeatedSwitchUnit] = []
    var conditionalSwitchLocations: [SwiftDebtCore.SourceLocation] = []
    var diagnostics: [AnalysisDiagnostic] = []

    mutating func append(_ other: Self) {
        dataClumpUnits += other.dataClumpUnits
        repeatedSwitchUnits += other.repeatedSwitchUnits
        conditionalSwitchLocations += other.conditionalSwitchLocations
        diagnostics += other.diagnostics
    }

    mutating func sortCanonical() {
        dataClumpUnits.sort(by: dataClumpUnitOrder)
        repeatedSwitchUnits.sort(by: repeatedSwitchUnitOrder)
        conditionalSwitchLocations.sort(by: sourceLocationOrder)
        diagnostics.sort(by: diagnosticOrder)
    }
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
