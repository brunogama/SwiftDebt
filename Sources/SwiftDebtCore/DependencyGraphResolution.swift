extension DependencyGraphBuilder {
    package func resolveType(
        _ name: String, from source: TypeKey, imports: Set<String>, types: [TypeKey: GraphTypeInfo]
    ) -> Resolution<TypeKey> {
        var parents = source.name.split(separator: ".").map(String.init)
        while !parents.isEmpty {
            let candidate = TypeKey(
                module: source.module, name: (parents + [name]).joined(separator: "."))
            if types[candidate] != nil { return .resolved(candidate) }
            parents.removeLast()
        }
        let sameModule = TypeKey(module: source.module, name: name)
        if types[sameModule] != nil { return .resolved(sameModule) }
        let parts = name.split(separator: ".").map(String.init)
        if parts.count > 1 {
            let qualified = TypeKey(
                module: parts[0], name: parts.dropFirst().joined(separator: "."))
            if types[qualified] != nil { return .resolved(qualified) }
        }
        let imported = imports.map { TypeKey(module: $0, name: name) }.filter { types[$0] != nil }
            .sorted {
                $0.displayName < $1.displayName
            }
        if imported.count == 1 { return .resolved(imported[0]) }
        if imported.count > 1 { return .ambiguous(imported) }
        let sameName = types.keys.filter { $0.name == name }.sorted {
            $0.displayName < $1.displayName
        }
        return sameName.count > 1 ? .ambiguous(sameName) : .unresolved
    }

    package func resolveCall(
        _ call: CallSiteFact, from source: FunctionInfo, functionNames: [String: [FunctionInfo]]
    ) -> Resolution<FunctionInfo> {
        let base = call.name.split(separator: ".").last.map(String.init) ?? call.name
        let display = "\(base)(\(call.labels))"
        var candidateNames: [String] = []
        if call.name.hasPrefix("self."), let owner = source.fact.owner {
            candidateNames.append("\(owner.displayName).\(display)")
        } else if call.name.hasPrefix("Self."), let owner = source.fact.owner {
            candidateNames.append("\(owner.displayName).\(display)")
        } else if call.name.contains("."), let owner = source.fact.owner {
            candidateNames.append("\(owner.module).\(call.name)(\(call.labels))")
        } else {
            if let owner = source.fact.owner {
                candidateNames.append("\(owner.displayName).\(display)")
            }
            candidateNames.append("\(source.module).\(display)")
        }
        let candidates = candidateNames.flatMap { functionNames[$0, default: []] }
            .filter { $0.nodeID != source.nodeID }
            .sorted(by: resolutionFunctionOrder)
        if candidates.count == 1 { return .resolved(candidates[0]) }
        if candidates.count > 1 { return .ambiguous(candidates) }
        return .unresolved
    }

    package func moduleNodeID(_ module: String) -> String { "module:\(module)" }

    package func typeNodeID(_ key: TypeKey) -> String { "type:\(key.displayName)" }

    package func callableNodeID(_ function: FunctionFacts) -> String {
        "callable:\(function.name)@\(function.location.file):\(function.location.line):\(function.location.column)"
    }

    package func callDisplayName(_ call: CallSiteFact) -> String {
        let base = call.name.split(separator: ".").last.map(String.init) ?? call.name
        return "\(base)(\(call.labels))"
    }

    package func isTestSource(path: String, module: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return module.hasSuffix("Tests") || module.hasSuffix("Test") || components.contains("Tests")
            || components.contains { $0.hasSuffix("Tests") } || path.hasSuffix("Tests.swift")
    }

    package func escapeDOT(_ value: String) -> String {
        var result = ""
        for character in value {
            if character == "\\" {
                result += "\\\\"
            } else if character == "\"" {
                result += "\\\""
            } else {
                result.append(character)
            }
        }
        return result
    }
}

private func resolutionFunctionOrder(
    _ lhs: DependencyGraphBuilder.FunctionInfo,
    _ rhs: DependencyGraphBuilder.FunctionInfo
) -> Bool {
    (
        lhs.fact.name, lhs.fact.location.file, lhs.fact.location.line, lhs.fact.location.column
    ) < (
        rhs.fact.name, rhs.fact.location.file, rhs.fact.location.line, rhs.fact.location.column
    )
}
