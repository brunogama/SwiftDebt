# R2 deterministic repository evidence

This document fixes the data shape and acceptance gate for the first R2
repository-aware rule slice. It is narrower than the complete R2 release in
`prd-r2.md`. Passing these implementation checks does not satisfy the labeled
corpus, independent review, calibrated performance, incremental state, or
SQVector release gates.

---

## Caller view

Library callers analyze an already selected source snapshot and receive one
transport-neutral report:

```swift
let report = try RepositoryAnalyzer().analyze(sources)
```

CLI callers opt into the same analysis and name the independent machine
artifact:

```sh
swift-debt analyze Sources \
  --repository-evidence .swift-debt/repository-evidence.json
```

Text output includes the repository rule explanations. JSON output remains the
released `AnalysisReport` schema 2, while the requested path receives the
separate repository evidence artifact.

---

## Report shape

The report has `reportKind` `swiftdebt-repository-evidence` and schema version
1. It records:

- generator version;
- normalized selected source paths and a SHA-256 digest over path, module, and
  source bytes;
- the exact repository-analysis configuration;
- Git revision and working-tree state when the selected root is a Git checkout;
- provider and capability provenance for each rule;
- complete or incomplete rule outcomes with machine-readable issues; and
- current-snapshot Detections with a non-durable selector, concrete location,
  decisive facts, compared units, predicate, limitations, refactoring
  direction, and DocC URL.

`AnalysisReport` schema 2, `DebtReport` schema 2, and compiler-evidence schema 1
do not gain repository fields.

---

## Observable rule scopes

### Data Clumps

A parameter/property element is the exact pair of its local identifier and its
formatting-independent SwiftSyntax type shape. For parameters, declaration
attributes, ownership modifiers, the declared type, and a variadic marker all
participate because they change how the value can be passed or used. Token
boundaries remain part of the canonical key, so `some P` and `someP` are
different types in this syntax-only comparison. Defaults do not participate.
Unnamed parameters and properties without an explicit type do not participate.

A Detection requires a closed group of at least three compatible elements that
occurs in at least two declaration units. Supported units in this slice are
function, method, initializer, and subscript parameter lists plus directly
declared instance-property groups in nominal types. The analyzer compares all
supported units across the selected source snapshot. Closure enumeration
intersects arbitrary numbers of units, and every set comparison consumes the
configured comparison budget before it runs.

The evidence remains syntax-only. Equal type spelling is compatible evidence;
different aliases that resolve to the same type are outside this slice. Equal
spelling in different name-binding contexts can still be unrelated, and the
explanation states that limitation.

### Repeated Switches

A Detection requires at least two switch statements with all of these exact
facts:

- the same textual module and enclosing nominal-type scope;
- the same simple identifier or member-access discriminator token sequence;
- the same ordered, formatting-independent case-label token sequences; and
- at least two switch cases.

Bodies do not participate in the dispatch-shape key. Order remains significant
because pattern and `where` matching can be order-sensitive. Switches containing
conditional-compilation case elements make this rule incomplete because this
syntax-only slice does not select an active compilation branch.

Canonical discriminator and case-label keys retain token boundaries. For
example, `case let value` and `case letvalue` cannot share a dispatch-shape key.

The discriminator is explicitly syntactic. The rule does not claim that two
equal spellings have compiler-resolved identity.

---

## Acceptance gate

This implementation slice passes when all checks below pass on the real library
and CLI surfaces:

1. Positive multi-file fixtures produce both rule Detections with concrete
   locations and full explanations.
2. Adversarial fixtures reject type mismatches, name mismatches, different
   switch discriminators, different case shapes, and equal switch shapes in
   different nominal scopes.
3. Parse failure, conditional switch cases, analysis-unit exhaustion, and
   comparison-budget exhaustion produce incomplete outcomes and never prove
   absence.
4. Reordered input and repeated CLI runs produce byte-identical schema 1 JSON.
5. The real CLI sidecar matches a checked-in golden file.
6. Opted-in text output matches a checked-in repository section golden.
7. The simultaneous schema 2 CLI JSON contains no repository evidence fields.
8. `swift build --build-tests && swift test` passes, or every unrelated existing
   failure is recorded exactly.

Decoded schema 1 artifacts recompute rule completion, capability, selector,
snapshot-digest, ordering, and summary invariants before callers can use
`isComplete` or `provesAbsence`. An empty rule list and contradictory complete
outcome are invalid artifacts rather than vacuous proof.

Each selector fingerprint is a domain-separated SHA-256 digest over the rule
identity, semantic revision, canonical decisive facts, their locations, and the
canonical compared units. Decoding recomputes that digest so facts and unit
references cannot be replaced independently of the selector.

Requested output paths are excluded from Git working-tree provenance. This
keeps repeated CLI runs byte-identical when the prior sidecar is otherwise the
only untracked change. Source count and byte limits fail before snapshot
hashing because a bounded run cannot truthfully publish a full content digest.
Fact limits are applied during extraction; the extractor retains at most one
unit beyond a configured per-rule limit so it can report exhaustion.

---

## Alternatives considered

Adding repository fields to `AnalysisReport` would give callers one document,
but it breaks the accepted schema boundary and forces syntax-only consumers to
understand repository completeness. It was rejected.

Modeling these as ordinary per-source `DebtRule` implementations would reuse the
R1 engine, but a source/rule pair cannot commit an exact cross-file enumeration
or explain a repository comparison. It was rejected.

A separate command could isolate the feature, but it would duplicate source
selection and configuration behavior. An opt-in sidecar on `analyze` preserves
one selection path and keeps the new wire contract independent.

---

## Remaining R2 release work

This slice does not claim the two rules are release-qualified as Supported. The
frozen 30-positive and 60-negative per-rule corpus, two-reviewer labels,
precision and recall record, calibrated performance artifact, incremental fact
cache, full relationship vocabulary, configurable policy gates, command/build
plugin acceptance, and published release benchmark remain required by the PRD.
