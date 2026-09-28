/// Parses a Rule Catalog Manifest (YAML, addendum H) into validated
/// `RuleDefinition`s. This is the compile-time validation half of ADR 0001
/// Q12 (the startup-time half is a downstream unit's responsibility).
/// `RuleManifestValidationPlugin` (Plugins/RuleManifestValidationPlugin, via
/// the `swift-debt-manifest-lint` executable target) wires `collectErrors`
/// into an actual `swift build` failure against
/// `Sources/SwiftDebtCore/RuleCatalog/Manifest/RuleCatalogManifest.yaml`.
public enum RuleManifestParser {
    /// Result of a best-effort parse: the rules that decoded and validated
    /// cleanly, plus every error encountered along the way.
    public typealias CollectedResult = (definitions: [RuleDefinition], errors: [RuleManifestError])

    /// Decodes and validates every rule in `yaml`, returning them in
    /// manifest order. Throws the first `RuleManifestError` encountered;
    /// callers that want every error at once should use
    /// ``collectErrors(yaml:)``.
    public static func parse(yaml: String) throws -> [RuleDefinition] {
        let entries = try decodeEntries(yaml: yaml)
        var definitions: [RuleDefinition] = []
        var seenIdentities: Set<String> = []
        for entry in entries {
            let definition = try RuleCatalogValidator.validate(entry: entry)
            guard seenIdentities.insert(entry.id).inserted else {
                throw RuleManifestError.duplicateIdentity(id: entry.id)
            }
            definitions.append(definition)
        }
        return definitions
    }

    /// Same as ``parse(yaml:)`` but never throws early: every entry is
    /// validated independently and every failure is returned, so a manifest
    /// with several bad rules reports all of them in one pass. Duplicate
    /// identities are still reported once each, at the point of the second
    /// (and later) occurrence.
    public static func collectErrors(yaml: String) -> CollectedResult {
        guard let entries = try? decodeEntries(yaml: yaml) else {
            let reason = malformedReason(yaml: yaml)
            return ([], [.malformedDocument(reason: reason)])
        }
        var definitions: [RuleDefinition] = []
        var errors: [RuleManifestError] = []
        var seenIdentities: Set<String> = []
        for entry in entries {
            if !seenIdentities.insert(entry.id).inserted {
                errors.append(.duplicateIdentity(id: entry.id))
                continue
            }
            do {
                definitions.append(try RuleCatalogValidator.validate(entry: entry))
            } catch let error as RuleManifestError {
                errors.append(error)
            } catch {
                errors.append(.malformedDocument(reason: "\(error)"))
            }
        }
        return (definitions, errors)
    }

    private static func decodeEntries(yaml: String) throws -> [RuleManifestEntry] {
        do {
            let node = try MinimalYAMLParser.parse(yaml)
            return try RuleManifestFile.parse(node).rules
        } catch let error as RuleManifestError {
            throw error
        } catch {
            throw RuleManifestError.malformedDocument(reason: "\(error)")
        }
    }

    private static func malformedReason(yaml: String) -> String {
        do {
            _ = try decodeEntries(yaml: yaml)
            return "unknown"
        } catch let error as RuleManifestError {
            if case .malformedDocument(let reason) = error {
                return reason
            }
            return "\(error)"
        } catch {
            return "\(error)"
        }
    }
}
