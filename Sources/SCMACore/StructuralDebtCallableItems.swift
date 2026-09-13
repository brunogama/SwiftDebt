extension StructuralDebtBuilder {
    func makeCallableItem(_ function: FunctionFacts) -> DebtItem {
        let itemID = "callable:\(function.name)"
        let location = DebtLocation(module: moduleName(for: function), source: function.location)
        let entity = DebtEntity(
            id: itemID,
            displayName: function.name,
            level: .callable,
            location: location
        )
        return DebtItem(
            id: itemID,
            entity: entity,
            evidence: [
                evidence(
                    itemID: itemID,
                    suffix: "cognitive-complexity",
                    kind: "swift.cognitive-complexity",
                    value: function.cognitiveComplexity,
                    threshold: 15,
                    weight: 2,
                    location: location,
                    note:
                        "Cognitive complexity adds current nesting to Swift flow breaks and ignores async, throws and await keywords."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "cyclomatic-complexity",
                    kind: "swift.cyclomatic-complexity",
                    value: function.complexity,
                    threshold: 20,
                    weight: 1,
                    location: location,
                    note: "Cyclomatic complexity follows the existing CCF decision policy, preserving SCMA metric behavior."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "nesting-depth",
                    kind: "swift.nesting-depth",
                    value: function.maxNestingDepth,
                    threshold: 5,
                    weight: 1,
                    location: location,
                    note: "Maximum nested Swift control-flow depth observed in this callable body."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "function-lines",
                    kind: "swift.function-lines",
                    value: function.codeLines,
                    threshold: 60,
                    weight: 0.5,
                    location: location,
                    note: "Physical token-bearing lines inside the callable body, excluding the outer signature and braces."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "parameter-count",
                    kind: "swift.parameter-count",
                    value: function.parameters,
                    threshold: 6,
                    weight: 0.5,
                    location: location,
                    note: "Declared callable parameters counted with the same parser facts as NOPF."
                ),
            ].sorted(by: evidenceOrder)
        )
    }

    func makeTypeItem(_ type: StructuralTypeFacts) -> DebtItem {
        let itemID = "type:\(type.key.displayName)"
        let location = DebtLocation(module: type.key.module, source: type.location)
        let entity = DebtEntity(
            id: itemID,
            displayName: type.key.displayName,
            level: .type,
            location: location
        )
        let oversizedScore = [
            normalized(type.codeLines, threshold: 500),
            normalized(type.methodCount, threshold: 30),
            normalized(type.propertyCount, threshold: 20),
            normalized(type.weightedMethodComplexity, threshold: 200),
        ].max() ?? 0
        let decomposition = type.callableNames.prefix(5).joined(separator: ", ")
        let decompositionNote = decomposition.isEmpty
            ? "No direct callables were available for deterministic decomposition evidence."
            : "Direct callables provide deterministic decomposition seeds: \(decomposition)."
        return DebtItem(
            id: itemID,
            entity: entity,
            evidence: [
                evidence(
                    itemID: itemID,
                    suffix: "type-lines",
                    kind: "swift.type-lines",
                    value: type.codeLines,
                    threshold: 500,
                    weight: 1,
                    location: location,
                    note: "Token-bearing lines across the selected type declaration and same-module extensions."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "method-count",
                    kind: "swift.method-count",
                    value: type.methodCount,
                    threshold: 30,
                    weight: 1,
                    location: location,
                    note: "Direct func, init and deinit bodies only; accessors remain excluded from NOMC."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "property-count",
                    kind: "swift.property-count",
                    value: type.propertyCount,
                    threshold: 20,
                    weight: 1,
                    location: location,
                    note: "Direct type-scope property bindings used by the existing NOGC calculation."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "weighted-method-complexity",
                    kind: "swift.weighted-method-complexity",
                    value: type.weightedMethodComplexity,
                    threshold: 200,
                    weight: 1,
                    location: location,
                    note: "Sum of existing CCF over direct methods and accessor bodies for this type."
                ),
                DebtEvidence(
                    id: "\(itemID):oversized-type",
                    kind: "swift.oversized-type",
                    weight: 1,
                    normalizedScore: oversizedScore,
                    rawValue:
                        "lines=\(type.codeLines);methods=\(type.methodCount);properties=\(type.propertyCount);wmcc=\(type.weightedMethodComplexity)",
                    location: location,
                    note: decompositionNote
                ),
            ].sorted(by: evidenceOrder)
        )
    }
}
