package struct StructuralTypeFacts: Sendable {
    package let key: TypeKey
    package let location: SourceLocation
    package let codeLines: Int
    package let propertyCount: Int
    package let methodCount: Int
    package let weightedMethodComplexity: Int
    package let callableNames: [String]

    package init(
        key: TypeKey,
        location: SourceLocation,
        codeLines: Int,
        propertyCount: Int,
        methodCount: Int,
        weightedMethodComplexity: Int,
        callableNames: [String]
    ) {
        self.key = key
        self.location = location
        self.codeLines = codeLines
        self.propertyCount = propertyCount
        self.methodCount = methodCount
        self.weightedMethodComplexity = weightedMethodComplexity
        self.callableNames = callableNames
    }
}

package struct StructuralDebtBuilder: Sendable {
    package init() {}

    package func items(
        files: [ParsedSource],
        types: [StructuralTypeFacts],
        functions: [FunctionFacts],
        duplicateBlocks: [DuplicateBlock]
    ) -> [DebtItem] {
        let duplicateLines = duplicateLinesByFile(duplicateBlocks)
        var items: [DebtItem] = []

        items += functions.sorted(by: functionOrder).map(makeCallableItem)
        items += types.sorted { $0.key.displayName < $1.key.displayName }.map(makeTypeItem)
        items += files.sorted { $0.path < $1.path }.map { file in
            makeFileItem(file: file, types: types, functions: functions, duplicateLines: duplicateLines)
        }
        for module in Set(files.map(\.module)).sorted() {
            let moduleFiles = files.filter { $0.module == module }.sorted { $0.path < $1.path }
            guard !moduleFiles.isEmpty else { continue }
            items.append(makeModuleItem(module: module, files: moduleFiles, types: types, functions: functions))
        }

        return items.sorted { lhs, rhs in
            if lhs.entity.level.rawValue != rhs.entity.level.rawValue {
                return lhs.entity.level.rawValue < rhs.entity.level.rawValue
            }
            return lhs.id < rhs.id
        }
    }

    func evidence(
        itemID: String,
        suffix: String,
        kind: String,
        value: Int,
        threshold: Int,
        weight: Double,
        location: DebtLocation,
        note: String
    ) -> DebtEvidence {
        DebtEvidence(
            id: "\(itemID):\(suffix)",
            kind: kind,
            weight: weight,
            normalizedScore: normalized(value, threshold: threshold),
            rawValue: "value=\(value)",
            location: location,
            note: note
        )
    }

    func normalized(_ value: Int, threshold: Int) -> Double {
        guard threshold > 0 else { return value > 0 ? 100 : 0 }
        return min(100, Double(value) * 100 / Double(threshold))
    }

    func functionOrder(_ lhs: FunctionFacts, _ rhs: FunctionFacts) -> Bool {
        if lhs.location != rhs.location { return locationOrder(lhs.location, rhs.location) }
        return lhs.name < rhs.name
    }

    func evidenceOrder(_ lhs: DebtEvidence, _ rhs: DebtEvidence) -> Bool {
        lhs.id < rhs.id
    }

    func moduleName(for function: FunctionFacts) -> String? {
        if let owner = function.owner { return owner.module }
        return function.name.split(separator: ".", maxSplits: 1).first.map(String.init)
    }

    private func duplicateLinesByFile(_ blocks: [DuplicateBlock]) -> [String: Set<Int>] {
        var lines: [String: Set<Int>] = [:]
        for block in blocks {
            add(block.first, to: &lines)
            add(block.second, to: &lines)
        }
        return lines
    }

    private func add(_ occurrence: DuplicateOccurrence, to lines: inout [String: Set<Int>]) {
        guard occurrence.startLine <= occurrence.endLine else { return }
        for line in occurrence.startLine...occurrence.endLine {
            lines[occurrence.file, default: []].insert(line)
        }
    }
}
