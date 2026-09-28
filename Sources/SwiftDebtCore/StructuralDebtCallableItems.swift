extension StructuralDebtBuilder {
    func makeCallableItem(_ function: FunctionFacts) -> DebtItem {
        let itemID = "callable:\(function.name)"
        let location = DebtLocation(module: moduleName(for: function), source: function.location)
        let specs = callableComplexitySpecs(function) + callableSizeSpecs(function)
        return DebtItem(
            id: itemID,
            entity: DebtEntity(
                id: itemID, displayName: function.name, level: .callable, location: location),
            evidence: evidence(itemID: itemID, location: location, specs: specs))
    }

    func makeTypeItem(_ type: StructuralTypeFacts) -> DebtItem {
        let itemID = "type:\(type.key.displayName)"
        let location = DebtLocation(module: type.key.module, source: type.location)
        var items = evidence(itemID: itemID, location: location, specs: typeEvidenceSpecs(type))
        items.append(oversizedTypeEvidence(type, itemID: itemID, location: location))
        return DebtItem(
            id: itemID,
            entity: DebtEntity(
                id: itemID, displayName: type.key.displayName, level: .type, location: location),
            evidence: items.sorted(by: evidenceOrder))
    }

    private func callableComplexitySpecs(_ function: FunctionFacts) -> [StructuralEvidenceSpec] {
        [
            StructuralEvidenceSpec(
                suffix: "cognitive-complexity", kind: "swift.cognitive-complexity",
                value: function.cognitiveComplexity, threshold: 15, weight: 2,
                note: "Cognitive complexity adds current nesting to Swift flow breaks and "
                    + "ignores async, throws and await keywords."),
            StructuralEvidenceSpec(
                suffix: "cyclomatic-complexity", kind: "swift.cyclomatic-complexity",
                value: function.complexity, threshold: 20, weight: 1,
                note: "Cyclomatic complexity follows the existing CCF decision policy, "
                    + "preserving SCMA metric behavior."),
            StructuralEvidenceSpec(
                suffix: "nesting-depth", kind: "swift.nesting-depth",
                value: function.maxNestingDepth, threshold: 5, weight: 1,
                note: "Maximum nested Swift control-flow depth observed in this callable body."),
        ]
    }

    private func callableSizeSpecs(_ function: FunctionFacts) -> [StructuralEvidenceSpec] {
        [
            StructuralEvidenceSpec(
                suffix: "function-lines", kind: "swift.function-lines",
                value: function.codeLines, threshold: 60, weight: 0.5,
                note: "Physical token-bearing lines inside the callable body, excluding the "
                    + "outer signature and braces."),
            StructuralEvidenceSpec(
                suffix: "parameter-count", kind: "swift.parameter-count",
                value: function.parameters, threshold: 6, weight: 0.5,
                note: "Declared callable parameters counted with the same parser facts as NOPF."),
        ]
    }

    private func typeEvidenceSpecs(_ type: StructuralTypeFacts) -> [StructuralEvidenceSpec] {
        [
            StructuralEvidenceSpec(
                suffix: "type-lines", kind: "swift.type-lines", value: type.codeLines,
                threshold: 500, weight: 1,
                note: "Token-bearing lines across the selected type declaration and "
                    + "same-module extensions."),
            StructuralEvidenceSpec(
                suffix: "method-count", kind: "swift.method-count", value: type.methodCount,
                threshold: 30, weight: 1,
                note: "Direct func, init and deinit bodies only; accessors remain excluded "
                    + "from NOMC."),
            StructuralEvidenceSpec(
                suffix: "property-count", kind: "swift.property-count", value: type.propertyCount,
                threshold: 20, weight: 1,
                note: "Direct type-scope property bindings used by the existing NOGC calculation."),
            StructuralEvidenceSpec(
                suffix: "weighted-method-complexity", kind: "swift.weighted-method-complexity",
                value: type.weightedMethodComplexity, threshold: 200, weight: 1,
                note: "Sum of existing CCF over direct methods and accessor bodies for this type."),
        ]
    }

    private func oversizedTypeEvidence(
        _ type: StructuralTypeFacts, itemID: String, location: DebtLocation
    ) -> DebtEvidence {
        let score = max(
            max(
                normalized(type.codeLines, threshold: 500),
                normalized(type.methodCount, threshold: 30)),
            max(
                normalized(type.propertyCount, threshold: 20),
                normalized(type.weightedMethodComplexity, threshold: 200)))
        let callables = type.callableNames.prefix(5).joined(separator: ", ")
        let note =
            callables.isEmpty
            ? "No direct callables were available for deterministic decomposition evidence."
            : "Direct callables provide deterministic decomposition seeds: \(callables)."
        return DebtEvidence(
            id: "\(itemID):oversized-type", kind: "swift.oversized-type", weight: 1,
            normalizedScore: score,
            rawValue: "lines=\(type.codeLines);methods=\(type.methodCount);properties="
                + "\(type.propertyCount);wmcc=\(type.weightedMethodComplexity)",
            location: location, note: note)
    }
}
