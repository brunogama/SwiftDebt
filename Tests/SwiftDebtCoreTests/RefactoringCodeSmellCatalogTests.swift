import Foundation
import SwiftDebtCore
import Testing

@Suite("Refactoring code smell catalog")
struct RefactoringCodeSmellCatalogTests {
    @Test("The published second-edition catalog has 24 distinct entries")
    func completeCatalog() {
        let entries = RefactoringCodeSmellCatalog.all
        let names = entries.map(\.name)

        #expect(entries.count == 24)
        #expect(Set(names).count == 24)
        #expect(Set(names) == Set(Self.secondEditionNames))
        #expect(entries.allSatisfy { !$0.minimumPredicate.isEmpty })
        #expect(entries.allSatisfy { !$0.requiredEvidence.isEmpty })
        #expect(entries.allSatisfy { !$0.scope.isEmpty })
        #expect(entries.allSatisfy { !$0.explanationContract.isEmpty })
    }

    @Test("Only shipped syntax smells claim Supported status")
    func supportClaims() {
        let supported = RefactoringCodeSmellCatalog.all.filter { $0.supportState == .supported }

        #expect(
            Set(supported.map(\.name)) == [
                "Long Function", "Long Parameter List", "Global Data", "Large Class",
            ])
        #expect(supported.allSatisfy { $0.ruleIdentity != nil && $0.semanticRevision == 1 })
        #expect(supported.allSatisfy { !$0.fixtureReferences.isEmpty })
        #expect(
            Dictionary(uniqueKeysWithValues: supported.map { ($0.name, $0.ruleIdentity ?? "") }) == [
                "Long Function": "swiftdebt.refactoring.long-function",
                "Long Parameter List": "swiftdebt.refactoring.long-parameter-list",
                "Global Data": "swiftdebt.refactoring.global-data",
                "Large Class": "swiftdebt.refactoring.large-class",
            ])
        #expect(
            RefactoringCodeSmellCatalog.named("Long Function")?.requiredEvidence.contains("top-level statement count")
                == true)
        #expect(
            RefactoringCodeSmellCatalog.named("Large Class")?.requiredEvidence.contains(
                "direct member declaration count") == true)
        #expect(RefactoringCodeSmellCatalog.named("Data Clumps")?.supportState == .research)
        #expect(RefactoringCodeSmellCatalog.named("Repeated Switches")?.supportState == .research)
        #expect(RefactoringCodeSmellCatalog.named("Feature Envy")?.supportState == .research)
        #expect(RefactoringCodeSmellCatalog.named("Middle Man")?.supportState == .research)
    }

    @Test("A consumer can serialize every catalog contract")
    func machineReadable() throws {
        let encoded = try JSONEncoder().encode(RefactoringCodeSmellCatalog.report)
        let decoded = try JSONDecoder().decode(RefactoringCodeSmellCatalogReport.self, from: encoded)

        #expect(decoded == RefactoringCodeSmellCatalog.report)
        #expect(decoded.reportKind == "swiftdebt-refactoring-code-smells")
        #expect(decoded.schemaVersion == 1)
    }

    @Test("An unknown catalog schema fails closed")
    func unknownSchema() throws {
        let encoded = try JSONEncoder().encode(RefactoringCodeSmellCatalog.report)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 2
        let changed = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RefactoringCodeSmellCatalogReport.self, from: changed)
        }

        object["schemaVersion"] = 1
        object["reportKind"] = "another-report"
        let changedKind = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RefactoringCodeSmellCatalogReport.self, from: changedKind)
        }
    }

    @Test("Malformed or incomplete rule references fail decoding")
    func malformedRuleReference() throws {
        let encoded = try JSONEncoder().encode(RefactoringCodeSmellCatalog.report)
        let original = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let cases: [(String?, Any?)] = [
            ("Invalid Name", 1),
            ("swiftdebt.refactoring.long-function", 0),
            ("swiftdebt.refactoring.long-function", nil),
            (nil, 1),
            ("invalid", 1),
            ("swiftdebt..invalid", 1),
        ]
        for (identity, revision) in cases {
            var object = original
            var entries = try #require(object["entries"] as? [[String: Any]])
            entries[0]["ruleIdentity"] = identity
            entries[0]["semanticRevision"] = revision
            object["entries"] = entries
            let changed = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(RefactoringCodeSmellCatalogReport.self, from: changed)
            }
        }
    }

    @Test("A catalog report rejects omitted, duplicated, or changed entries")
    func noncanonicalEntries() throws {
        let encoded = try JSONEncoder().encode(RefactoringCodeSmellCatalog.report)
        let original = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let entries = try #require(original["entries"] as? [[String: Any]])
        var changedPredicate = entries
        changedPredicate[0]["minimumPredicate"] = "A different predicate."
        var changedSupport = entries
        changedSupport[0]["supportState"] = "research"
        let variants = [
            Array(entries.dropLast()),
            Array(entries.dropLast()) + [entries[0]],
            changedPredicate,
            changedSupport,
        ]

        for variant in variants {
            var object = original
            object["entries"] = variant
            let changed = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(RefactoringCodeSmellCatalogReport.self, from: changed)
            }
        }
    }

    @Test("The human coverage table agrees with the machine catalog")
    func documentationParity() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let document = try String(
            contentsOf: repository.appendingPathComponent("docs/REFACTORING_CODE_SMELLS.md"),
            encoding: .utf8
        )
        let start = try #require(document.range(of: "## Evidence map\n"))
        let evidenceMap = document[start.upperBound...].components(separatedBy: "\n---\n")[0]
        let documented: [String: [String]] = Dictionary(
            uniqueKeysWithValues: evidenceMap.split(separator: "\n").compactMap { line in
                let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                guard cells.count == 3, Self.secondEditionNames.contains(cells[0]) else { return nil }
                return (cells[0], [cells[1], cells[2]])
            })
        let expected = Dictionary(
            uniqueKeysWithValues: RefactoringCodeSmellCatalog.all.map { entry in
                (entry.name, [entry.minimumPredicate, entry.supportState.documentationName])
            })

        #expect(documented == expected)
    }

    private static let secondEditionNames = [
        "Mysterious Name", "Duplicated Code", "Long Function", "Long Parameter List",
        "Global Data", "Mutable Data", "Divergent Change", "Shotgun Surgery",
        "Feature Envy", "Data Clumps", "Primitive Obsession", "Repeated Switches",
        "Loops", "Lazy Element", "Speculative Generality", "Temporary Field",
        "Message Chains", "Middle Man", "Insider Trading", "Large Class",
        "Alternative Classes with Different Interfaces", "Data Class", "Refused Bequest", "Comments",
    ]
}

extension CodeSmellSupportState {
    fileprivate var documentationName: String {
        switch self {
        case .supported: "Supported"
        case .partiallySupported: "Partially Supported"
        case .research: "Research"
        case .notReliablyObservable: "Not Reliably Observable"
        }
    }
}
