extension StructuralDebtBuilder {
    func makeFileItem(
        file: ParsedSource,
        types: [StructuralTypeFacts],
        functions: [FunctionFacts],
        duplicateLines: [String: Set<Int>]
    ) -> DebtItem {
        let itemID = "file:\(file.path)"
        let firstLine = file.lines.first?.number ?? 1
        let location = DebtLocation(
            module: file.module, file: file.path, line: firstLine, column: 1)
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
            evidence: evidence(
                itemID: itemID, location: location,
                specs: fileEvidenceSpecs(
                    file: file, typeCount: fileTypes, functionCount: fileFunctions,
                    duplicatedLineCount: duplicatedLineCount))
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
            evidence: evidence(
                itemID: itemID, location: location,
                specs: moduleEvidenceSpecs(
                    lineCount: moduleLines, fileCount: files.count, typeCount: moduleTypes,
                    functionCount: moduleFunctions))
        )
    }

    private func fileEvidenceSpecs(
        file: ParsedSource, typeCount: Int, functionCount: Int, duplicatedLineCount: Int
    ) -> [StructuralEvidenceSpec] {
        [
            StructuralEvidenceSpec(
                suffix: "file-lines", kind: "swift.file-lines", value: file.lines.count,
                threshold: 1_000, weight: 1,
                note: "Token-bearing Swift lines in this parsed source file."),
            StructuralEvidenceSpec(
                suffix: "file-type-count", kind: "swift.file-type-count", value: typeCount,
                threshold: 20, weight: 0.5,
                note: "Selected nominal declarations and extensions located in this file."),
            StructuralEvidenceSpec(
                suffix: "file-callable-count", kind: "swift.file-callable-count",
                value: functionCount, threshold: 80, weight: 0.5,
                note: "Implemented functions and accessors located in this file."),
            StructuralEvidenceSpec(
                suffix: "duplicate-lines", kind: "swift.duplicate-lines",
                value: duplicatedLineCount, threshold: 20, weight: 1,
                note: "Unique physical lines in this file that participate in exact "
                    + "token-normalized clone blocks."),
        ]
    }

    private func moduleEvidenceSpecs(
        lineCount: Int, fileCount: Int, typeCount: Int, functionCount: Int
    ) -> [StructuralEvidenceSpec] {
        [
            StructuralEvidenceSpec(
                suffix: "module-lines", kind: "swift.module-lines", value: lineCount,
                threshold: 5_000, weight: 1,
                note: "Token-bearing Swift lines summed across parsed files in this module."),
            StructuralEvidenceSpec(
                suffix: "module-file-count", kind: "swift.module-file-count", value: fileCount,
                threshold: 100, weight: 0.5, note: "Parsed Swift source files in this module."),
            StructuralEvidenceSpec(
                suffix: "module-type-count", kind: "swift.module-type-count", value: typeCount,
                threshold: 100, weight: 0.5, note: "Selected types aggregated for this module."),
            StructuralEvidenceSpec(
                suffix: "module-callable-count", kind: "swift.module-callable-count",
                value: functionCount, threshold: 400, weight: 0.5,
                note: "Implemented callables aggregated for this module."),
        ]
    }
}
