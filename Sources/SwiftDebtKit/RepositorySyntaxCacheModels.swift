import Foundation
import SwiftDebtCore

struct RepositorySyntaxCacheEntry: Codable, Equatable, Sendable {
    let path: String
    let module: String
    let contentDigest: RepositoryDigest
    let incomingBudget: RepositorySyntaxFactBudget
    let facts: RepositorySyntaxFacts

    func validate() throws {
        let normalizedPath = try SourcePath(path).rawValue
        guard normalizedPath == path,
            !module.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            incomingBudget.canContain(facts),
            facts.isCanonical(for: path)
        else {
            throw RepositorySyntaxCacheValidationError.invalidEntry(path)
        }
    }
}

struct RepositorySyntaxFactBudget: Codable, Equatable, Sendable {
    let dataClumpUnits: Int
    let repeatedSwitchFacts: Int

    init(maximumAnalysisUnitsPerRule: Int) {
        let (incremented, overflowed) = maximumAnalysisUnitsPerRule.addingReportingOverflow(1)
        let materializationLimit = overflowed ? Int.max : incremented
        dataClumpUnits = materializationLimit
        repeatedSwitchFacts = materializationLimit
    }

    init(dataClumpUnits: Int, repeatedSwitchFacts: Int) {
        self.dataClumpUnits = dataClumpUnits
        self.repeatedSwitchFacts = repeatedSwitchFacts
    }

    func canContain(_ facts: RepositorySyntaxFacts) -> Bool {
        dataClumpUnits >= facts.dataClumpUnits.count
            && repeatedSwitchFacts
                >= facts.repeatedSwitchUnits.count + facts.conditionalSwitchLocations.count
    }

    func consuming(_ facts: RepositorySyntaxFacts) throws -> Self {
        guard canContain(facts) else {
            throw RepositorySyntaxCacheValidationError.factBudgetExceeded
        }
        return Self(
            dataClumpUnits: dataClumpUnits - facts.dataClumpUnits.count,
            repeatedSwitchFacts:
                repeatedSwitchFacts - facts.repeatedSwitchUnits.count - facts.conditionalSwitchLocations.count
        )
    }
}

enum RepositorySyntaxCacheValidationError: Error {
    case factBudgetExceeded
    case integrityMismatch
    case invalidEntry(String)
    case invalidReportKind
    case noncanonicalEntries
    case unsupportedSchema
}

extension RepositorySyntaxCacheCompatibility {
    static func current(configuration: RepositoryAnalysisConfiguration) -> Self {
        Self(
            cacheSchemaVersion: RepositorySyntaxCacheDocument.schemaVersion,
            factSchemaVersion: 1,
            projectionRevision: "repository-syntax-facts-v1",
            provider: RepositorySyntaxCacheProviderIdentity(
                name: "SwiftSyntax",
                packageVersion: "602.0.0",
                sourceRevision: "4799286537280063c85a32f09884cfbca301b1a1"
            ),
            rules: [
                RepositorySyntaxCacheRuleIdentity(
                    ruleIdentity: DataClumpsRepositoryRule.identity,
                    semanticRevision: DataClumpsRepositoryRule.semanticRevision
                ),
                RepositorySyntaxCacheRuleIdentity(
                    ruleIdentity: RepeatedSwitchesRepositoryRule.identity,
                    semanticRevision: RepeatedSwitchesRepositoryRule.semanticRevision
                ),
            ],
            maximumAnalysisUnitsPerRule: configuration.maximumAnalysisUnitsPerRule
        )
    }

    func validateCanonicalForm() throws {
        let ordered = rules.sorted {
            if $0.ruleIdentity != $1.ruleIdentity { return $0.ruleIdentity < $1.ruleIdentity }
            return $0.semanticRevision < $1.semanticRevision
        }
        guard cacheSchemaVersion > 0,
            factSchemaVersion > 0,
            !projectionRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !provider.packageVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !provider.sourceRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            maximumAnalysisUnitsPerRule > 0,
            !rules.isEmpty,
            rules == ordered,
            Set(rules.map(\.ruleIdentity)).count == rules.count,
            rules.allSatisfy({
                !$0.ruleIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.semanticRevision > 0
            })
        else {
            throw RepositorySyntaxCacheValidationError.invalidEntry("compatibility")
        }
    }

    func invalidationReasons(
        comparedTo expected: Self
    ) -> [RepositorySyntaxCacheInvalidationReason] {
        var reasons: [RepositorySyntaxCacheInvalidationReason] = []
        if cacheSchemaVersion != expected.cacheSchemaVersion { reasons.append(.schemaMismatch) }
        if factSchemaVersion != expected.factSchemaVersion { reasons.append(.factSchemaMismatch) }
        if projectionRevision != expected.projectionRevision { reasons.append(.projectionChanged) }
        if provider != expected.provider { reasons.append(.providerChanged) }
        if rules != expected.rules { reasons.append(.ruleSemanticsChanged) }
        if maximumAnalysisUnitsPerRule != expected.maximumAnalysisUnitsPerRule {
            reasons.append(.configurationChanged)
        }
        return reasons
    }
}

extension RepositorySyntaxFacts {
    func isCanonical(for path: String) -> Bool {
        guard dataClumpUnits == dataClumpUnits.sorted(by: dataClumpUnitOrder),
            repeatedSwitchUnits == repeatedSwitchUnits.sorted(by: repeatedSwitchUnitOrder),
            conditionalSwitchLocations == conditionalSwitchLocations.sorted(by: sourceLocationOrder),
            diagnostics == diagnostics.sorted(by: diagnosticOrder)
        else { return false }
        let locations =
            dataClumpUnits.map(\.location)
            + repeatedSwitchUnits.map(\.location)
            + conditionalSwitchLocations
            + diagnostics.map(\.location)
        return locations.allSatisfy { $0.file == path && $0.line > 0 && $0.column > 0 }
            && dataClumpUnits.allSatisfy {
                !$0.displayName.isEmpty && !$0.elements.isEmpty
                    && $0.elements.allSatisfy {
                        !$0.name.isEmpty && !$0.normalizedType.tokens.isEmpty
                    }
            }
            && repeatedSwitchUnits.allSatisfy {
                !$0.scope.isEmpty && !$0.displayName.isEmpty && !$0.discriminator.tokens.isEmpty
                    && $0.caseShape.count >= 2 && $0.caseShape.allSatisfy { !$0.tokens.isEmpty }
            }
            && diagnostics.allSatisfy { !$0.message.isEmpty }
    }
}
