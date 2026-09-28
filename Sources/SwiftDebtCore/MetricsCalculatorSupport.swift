extension MetricsCalculator {
    package func enrichDebtItems(
        _ items: [DebtItem],
        functionalEvidence: [DebtEvidence],
        dependencyContexts: [DependencyContext]
    ) -> [DebtItem] {
        let dependencyEvidenceByID = Dictionary(grouping: dependencyContexts, by: { $0.entity.id })
            .mapValues { contexts in contexts.flatMap(\.evidence) }
        return items.map { item in
            var evidence = item.evidence
            evidence += functionalEvidence.filter { candidate in
                guard let location = candidate.location else { return false }
                if item.entity.level == .callable {
                    return location == item.entity.location
                }
                return item.entity.level == .file && location.file == item.entity.location.file
            }
            evidence += dependencyEvidenceByID[item.entity.id, default: []]
            return DebtItem(
                id: item.id,
                entity: item.entity,
                evidence: evidence.sorted { lhs, rhs in
                    if lhs.id != rhs.id { return lhs.id < rhs.id }
                    if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
                    return lhs.rawValue < rhs.rawValue
                }
            )
        }.sorted { lhs, rhs in
            if lhs.entity.level.rawValue != rhs.entity.level.rawValue {
                return lhs.entity.level.rawValue < rhs.entity.level.rawValue
            }
            return lhs.id < rhs.id
        }
    }

    package func aggregate(
        _ fragments: [TypeFragment], scope: TypeScope, diagnostics: inout [AnalysisDiagnostic]
    ) -> [TypeKey: Aggregate] {
        var result: [TypeKey: Aggregate] = [:]
        for (key, group) in Dictionary(grouping: fragments, by: \.key) {
            let bases = group.filter { !$0.isExtension }
            guard let base = bases.first else { continue }
            guard scope == .nominals || base.kind == "class" else { continue }
            guard bases.count == 1 else {
                diagnostics.append(
                    AnalysisDiagnostic(
                        severity: .warning,
                        message:
                            "Ambiguous declarations for \(key.displayName); conditional compilation is not evaluated. Type metrics omitted.",
                        location: bases.sorted { locationOrder($0.location, $1.location) }[0]
                            .location
                    ))
                continue
            }
            result[key] = Aggregate(
                key: key, location: base.location, lines: group.reduce(0) { $0 + $1.codeLines },
                fields: group.reduce(into: Set<String>()) { $0.formUnion($1.propertyNames) },
                fragments: group
            )
        }
        return result
    }

    package func couplingEdges(_ types: [TypeKey: Aggregate]) -> [CouplingEdge] {
        var edges: Set<CouplingEdge> = []
        for type in types.values {
            for fragment in type.fragments {
                for name in fragment.referencedTypes {
                    guard
                        let other = resolve(
                            name, from: type.key, imports: fragment.importedModules, types: types),
                        other != type.key
                    else { continue }
                    let endpoints = [type.key.displayName, other.displayName].sorted()
                    edges.insert(CouplingEdge(first: endpoints[0], second: endpoints[1]))
                }
            }
        }
        return edges.sorted { ($0.first, $0.second) < ($1.first, $1.second) }
    }

    package func resolve(
        _ name: String, from source: TypeKey, imports: Set<String>, types: [TypeKey: Aggregate]
    ) -> TypeKey? {
        var parents = source.name.split(separator: ".").map(String.init)
        while !parents.isEmpty {
            let candidate = TypeKey(
                module: source.module, name: (parents + [name]).joined(separator: "."))
            if types[candidate] != nil { return candidate }
            parents.removeLast()
        }
        let sameModule = TypeKey(module: source.module, name: name)
        if types[sameModule] != nil { return sameModule }
        let parts = name.split(separator: ".").map(String.init)
        if parts.count > 1 {
            let qualified = TypeKey(
                module: parts[0], name: parts.dropFirst().joined(separator: "."))
            if types[qualified] != nil { return qualified }
        }
        let imported = imports.map { TypeKey(module: $0, name: name) }.filter { types[$0] != nil }
        return imported.count == 1 ? imported[0] : nil
    }

    package func measurementNote(_ metric: Metric) -> String? {
        switch metric {
        case .nogc:
            "Class-scope property bindings (let/var, stored/computed), not true file-global "
                + "variables."
        case .noav:
            "Conservative lexical field-use estimate; explicit self/Self and unshadowed bare "
                + "names. No compiler binding resolution."
        case .nocc:
            "Undirected graph of resolved syntactic nominal references within selected inputs; "
                + "not a compiler call graph."
        case .dc:
            "Native exact token-normalized line clones, not Lizard. Duplicated-line total is the "
                + "union across all occurrences."
        case .ccf:
            "Documented decision-node policy; nested closures and local functions do not inflate "
                + "enclosing functions."
        case .wmcc:
            "Sum of CCF over direct methods and accessor bodies; nested closures and local "
                + "functions do not inflate enclosing functions."
        case .nomc:
            "Implemented func/init/deinit only; property and subscript accessors are not methods."
        default: nil
        }
    }
}
