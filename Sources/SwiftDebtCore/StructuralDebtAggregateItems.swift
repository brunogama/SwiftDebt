extension StructuralDebtBuilder {
    func makeFileItem(
        file: ParsedSource,
        types: [StructuralTypeFacts],
        functions: [FunctionFacts],
        duplicateLines: [String: Set<Int>]
    ) -> DebtItem {
        let itemID = "file:\(file.path)"
        let firstLine = file.lines.first?.number ?? 1
        let location = DebtLocation(module: file.module, file: file.path, line: firstLine, column: 1)
        let entity = DebtEntity(
            id: itemID,
            displayName: file.path,
            level: .file,
            location: location
        )
        let fileTypes = types.filter { $0.location.file == file.path }.count
        let fileFunctions = functions.filter { $0.location.file == file.path }.count
        let duplicatedLineCount = duplicateLines[file.path, default: []].count
        return DebtItem(
            id: itemID,
            entity: entity,
            evidence: [
                evidence(
                    itemID: itemID,
                    suffix: "file-lines",
                    kind: "swift.file-lines",
                    value: file.lines.count,
                    threshold: 1_000,
                    weight: 1,
                    location: location,
                    note: "Token-bearing Swift lines in this parsed source file."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "file-type-count",
                    kind: "swift.file-type-count",
                    value: fileTypes,
                    threshold: 20,
                    weight: 0.5,
                    location: location,
                    note: "Selected nominal declarations and extensions located in this file."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "file-callable-count",
                    kind: "swift.file-callable-count",
                    value: fileFunctions,
                    threshold: 80,
                    weight: 0.5,
                    location: location,
                    note: "Implemented functions and accessors located in this file."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "duplicate-lines",
                    kind: "swift.duplicate-lines",
                    value: duplicatedLineCount,
                    threshold: 20,
                    weight: 1,
                    location: location,
                    note: "Unique physical lines in this file that participate in exact token-normalized clone blocks."
                ),
            ].sorted(by: evidenceOrder)
        )
    }

    func makeModuleItem(
        module: String,
        files: [ParsedSource],
        types: [StructuralTypeFacts],
        functions: [FunctionFacts]
    ) -> DebtItem {
        let anchor = files[0]
        let firstLine = anchor.lines.first?.number ?? 1
        let location = DebtLocation(module: module, file: anchor.path, line: firstLine, column: 1)
        let itemID = "module:\(module)"
        let moduleTypes = types.filter { $0.key.module == module }.count
        let moduleFunctions = functions.filter { moduleName(for: $0) == module }.count
        let moduleLines = files.reduce(0) { $0 + $1.lines.count }
        return DebtItem(
            id: itemID,
            entity: DebtEntity(
                id: itemID,
                displayName: module,
                level: .module,
                location: location
            ),
            evidence: [
                evidence(
                    itemID: itemID,
                    suffix: "module-lines",
                    kind: "swift.module-lines",
                    value: moduleLines,
                    threshold: 5_000,
                    weight: 1,
                    location: location,
                    note: "Token-bearing Swift lines summed across parsed files in this module."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "module-file-count",
                    kind: "swift.module-file-count",
                    value: files.count,
                    threshold: 100,
                    weight: 0.5,
                    location: location,
                    note: "Parsed Swift source files in this module."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "module-type-count",
                    kind: "swift.module-type-count",
                    value: moduleTypes,
                    threshold: 100,
                    weight: 0.5,
                    location: location,
                    note: "Selected types aggregated for this module."
                ),
                evidence(
                    itemID: itemID,
                    suffix: "module-callable-count",
                    kind: "swift.module-callable-count",
                    value: moduleFunctions,
                    threshold: 400,
                    weight: 0.5,
                    location: location,
                    note: "Implemented callables aggregated for this module."
                ),
            ].sorted(by: evidenceOrder)
        )
    }
}
