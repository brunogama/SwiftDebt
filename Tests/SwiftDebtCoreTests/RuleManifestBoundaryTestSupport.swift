import Foundation
import Testing

struct MalformedManifestCase: Sendable, CustomTestStringConvertible {
    let name: String
    let yaml: String
    let expectedReason: String

    var testDescription: String { name }
}

let boundaryRuleManifest = """
    rules:
      - id: boundary.rule
        semanticRevision: 1
        title: Boundary rule
        category: style
        scope: syntax
        detectionMode: deterministic
        requirements:
          - syntax
        evidence:
          required:
            fact:
              key: syntaxNode
              kind: syntax
        supportState: supported
        provenance:
          researchItem: 1
    """

let boundaryEvidenceBlock = """
        evidence:
          required:
            fact:
              key: syntaxNode
              kind: syntax
    """

func boundaryManifestReplacing(_ original: String, with replacement: String = "") -> String {
    boundaryRuleManifest.replacingOccurrences(of: original, with: replacement)
}

let malformedManifestCases = [
    MalformedManifestCase(
        name: "rules is not a sequence",
        yaml: "rules: scalar",
        expectedReason: "'rules' must be a sequence"
    ),
    MalformedManifestCase(
        name: "rule omits evidence",
        yaml: boundaryManifestReplacing(boundaryEvidenceBlock),
        expectedReason: "rule 'boundary.rule' is missing 'evidence'"
    ),
    MalformedManifestCase(
        name: "rule omits a required string",
        yaml: boundaryManifestReplacing("    title: Boundary rule\n"),
        expectedReason: "manifest entry is missing required field 'title'"
    ),
    MalformedManifestCase(
        name: "semantic revision is not an integer",
        yaml: boundaryManifestReplacing("semanticRevision: 1", with: "semanticRevision: one"),
        expectedReason: "manifest entry field 'semanticRevision' must be an integer"
    ),
    MalformedManifestCase(
        name: "requirements is not a sequence",
        yaml: boundaryManifestReplacing(
            "    requirements:\n      - syntax", with: "    requirements: syntax"),
        expectedReason: "'requirements' must be a sequence of strings"
    ),
    MalformedManifestCase(
        name: "a requirement is not a string",
        yaml: boundaryManifestReplacing("      - syntax", with: "      - nested: syntax"),
        expectedReason: "'requirements' entries must be strings"
    ),
    MalformedManifestCase(
        name: "evidence omits its required predicate",
        yaml: boundaryManifestReplacing(
            boundaryEvidenceBlock,
            with: "    evidence:\n      optional: []"),
        expectedReason: "'evidence' is missing its required predicate"
    ),
    MalformedManifestCase(
        name: "optional evidence is not a sequence",
        yaml: boundaryManifestReplacing(
            boundaryEvidenceBlock,
            with: boundaryEvidenceBlock + "\n      optional: scalar"),
        expectedReason: "'evidence.optional' must be a sequence"
    ),
    MalformedManifestCase(
        name: "provenance research item is not an integer",
        yaml: boundaryManifestReplacing("researchItem: 1", with: "researchItem: one"),
        expectedReason: "'provenance.researchItem' must be an integer"
    ),
    MalformedManifestCase(
        name: "evidence predicate is not a mapping",
        yaml: boundaryManifestReplacing(
            boundaryEvidenceBlock,
            with: "    evidence:\n      required: syntax"),
        expectedReason: "an evidence predicate node must be a mapping"
    ),
    MalformedManifestCase(
        name: "evidence predicate has an unknown operator",
        yaml: boundaryManifestReplacing(
            boundaryEvidenceBlock,
            with: "    evidence:\n      required:\n        unknown: syntax"),
        expectedReason: "must have exactly one of fact/all/any/not"
    ),
    MalformedManifestCase(
        name: "fact omits its kind",
        yaml: boundaryManifestReplacing(
            boundaryEvidenceBlock,
            with: "    evidence:\n      required:\n        fact:\n          key: syntaxNode"),
        expectedReason: "a 'fact' node requires string 'key' and 'kind' fields"
    ),
    MalformedManifestCase(
        name: "predicate children are not a sequence",
        yaml: boundaryManifestReplacing(
            boundaryEvidenceBlock,
            with: "    evidence:\n      required:\n        all: syntax"),
        expectedReason: "'all' must be a sequence"
    ),
]
