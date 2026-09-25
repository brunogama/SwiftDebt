# SwiftDebt R2: Evidence-Backed Repository Code Smells

| Field           | Value                                                |
| --------------- | ---------------------------------------------------- |
| Status          | Draft for approval                                   |
| Release         | R2                                                   |
| Updated         | 2026-09-24                                           |
| Predecessor     | R1 current-source rule observation                   |
| Product surface | Swift library, CLI, command plugin, and build plugin |

---

## Executive Summary

SwiftDebt R2 extends the R1 rule engine from syntax observations within one
`SourceUnit` to evidence-backed code-smell analysis across a selected repository
snapshot. R2 targets the 24 code smells named in Chapter 3 of Martin Fowler's
_Refactoring, Second Edition_. It does not claim that every smell can be proven
by static analysis.

R2 keeps deterministic syntax and structural evidence as the primary path. It
adds repository facts, cross-file relationships, capability-aware rule
execution, incremental derived state, and evidence-rich explanations. Optional
lexical, structural, relationship, and semantic similarity may retrieve
candidates. A similarity score never proves technical debt and never produces a
`Detection` without rule-specific validation.

The selected optional local candidate index is
[`brunogama/sqvector-swift`](https://github.com/brunogama/sqvector-swift),
referred to as SQVector in this PRD. The intended integration product is
`SQVectorStatic` from the repository's nested `Packages/SQVector` package; its
module remains `SQVector`, and the existing automatic library product remains
available. R2 consumes a qualified revision through an R2-owned adapter.
SQVector is not required for syntax-only or deterministic repository analysis.
Its inclusion must not raise SwiftDebt's existing deployment targets or
introduce source transmission.

R2 remains a current-snapshot analysis release. It does not introduce durable
Finding identity, reconciliation, open or resolved states, suppression history,
or debt lifecycle. Those capabilities require a later product contract.

---

## Existing-State Constraints

R2 builds on released behavior. The following are constraints, not new R2
claims:

- A `DebtRule` proposes source syntax and a single-line message.
- The R1 engine executes and validates each selected rule and `SourceUnit` pair
  atomically.
- A committed empty result proves absence only for that rule, that source, and
  that analyzed snapshot.
- Parse failure, unsupported analysis, rule failure, or invalid emission never
  proves absence.
- The canonical rule observation is a `Detection` containing rule identity,
  semantic revision, severity, source location, and message.
- R1 has no reconciliation or Detection lifecycle.
- The existing Fowler catalog has 24 entries: Long Function, Long Parameter
  List, Global Data, and Large Class are active; the other 20 are later work.
- Rule observations are advisory by default. `--fail-on-violation` is the
  explicit CI gate, while incomplete analysis remains an error.
- Compiler-backed facts follow
  [ADR 0001](adr/0001-compiler-evidence-sidecar-boundary.md): they use a
  versioned sidecar with source identity and explicit `available`,
  `unavailable`, or `ambiguous` capability states. Parseable compiler output by
  itself is not compiler-backed evidence.
- `AnalysisReport` schema 2 and `DebtReport` schema 2 remain syntax-only
  contracts. R2 must not silently add repository or compiler evidence to either
  schema.

The current catalog and its completion predicate are documented in
[Refactoring second-edition code smells](REFACTORING_CODE_SMELLS.md).

---

## Product Objective

R2 gives Swift developers actionable, reproducible answers to this question:

> Which Fowler code-smell patterns are evidenced across this exact source
> snapshot, and what facts justify each observation?

R2 succeeds when a developer can run one local command, understand why each
Detection exists, distinguish unavailable evidence from a clean result, and use
the same evidence contract in CI or through the library API.

### Goals

- Expand the Fowler catalog with repository-aware rules that meet an explicit
  evidence and quality bar.
- Preserve R1's truth semantics while adding cross-file scope.
- Make every supported code-smell claim inspectable and reproducible.
- Keep optional similarity local, lazy, replaceable, and subordinate to rule
  validation.
- Reuse compatible derived state without hiding invalidation or stale evidence.
- Publish measurable accuracy, false-positive, retrieval-quality, and
  performance results.

### Product principles

1. Missing evidence is not evidence of absence.
2. Similarity retrieves candidates; rule predicates decide Detections.
3. A smell name is a catalog entry, not a support claim.
4. A current Detection is not a durable Finding.
5. Deterministic evidence is preferred whenever it answers the question.
6. Expensive capabilities are initialized only when a selected rule needs them.
7. Provider, capability, version, and source provenance are part of the result.
8. Default operation is local and sends no source or projection off-device.

### Key terms

| Term                  | Meaning in R2                                                                                                                                |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Repository snapshot   | The exact selected source scope plus its content identity, configuration, and available provider identities for one analysis run.            |
| Analysis unit         | A source-located file, declaration, or closure from which R2 derives facts. It is not a durable debt identity.                               |
| Candidate             | A unit or pair selected for rule validation. Retrieval does not make it a Detection.                                                         |
| Detection             | The canonical current-snapshot observation emitted only after a rule commits validated evidence.                                             |
| Finding               | A future durable lifecycle concept. R2 neither creates nor reconciles Findings.                                                              |
| Complete rule outcome | Every required unit, capability, and exact enumeration path committed for the declared scope.                                                |
| Supported smell       | A catalog entry whose declared observable scope passes every evidence, accuracy, explanation, determinism, and performance gate in this PRD. |

---

## Users and Core Workflows

### Repository maintainer

The maintainer runs `swift-debt analyze .`, receives deterministic active-rule
results plus any enabled R2 repository results, and opens a detailed explanation
for a Detection. The explanation identifies the decisive facts, analyzed scope,
threshold or predicate, and any unavailable optional evidence.

### Platform or architecture team

The team checks a versioned configuration into the repository, runs the same
analysis in CI, and opts into failure only for rules and support states it has
approved. When a selected rule requires compiler evidence, similarity, or a
bounded provider, a missing or incompatible provider, exhausted work budget, or
provider failure makes that rule's affected scope incomplete rather than clean.
Unrelated rules with sufficient evidence may still complete.

### Rule author

The author declares the evidence capabilities a rule requires, supplies
positive and adversarial fixtures, and verifies the rule against a labeled
corpus. The author does not import SQVector or an embedding framework from rule
semantics.

### Tool or coding-agent consumer

The consumer reads a versioned machine report containing current Detections,
evidence, completeness, and provenance. The consumer can cite why a Detection
exists without inferring lifecycle state or treating an absent result from an
incomplete run as resolved debt.

---

## R2 Release Boundary

| Area                  | R2 commitment                                                                                                                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R1 compatibility      | Preserve the four active syntax smells, their atomic rule and source execution, advisory default, and failure semantics.                                                                               |
| Repository analysis   | Add deterministic repository units, cross-file structural indexes, and explicit relationship evidence.                                                                                                 |
| New Supported smells  | Graduate Data Clumps and Repeated Switches using deterministic repository evidence. Keep compiler-dependent Feature Envy and Middle Man in Research until a compiler provider is separately qualified. |
| Hybrid similarity     | Ship an opt-in candidate-generation path and a measured research evaluation for Alternative Classes with Different Interfaces. It is not a Supported smell in R2.                                      |
| Local vector index    | Qualify `SQVectorStatic` from SQVector's nested `Packages/SQVector` package as the selected optional local candidate-index product, isolated behind a SwiftDebt interface.                             |
| Fowler catalog        | Publish all 24 entries with support state, minimum predicate, required capability, known blind spots, and fixture evidence.                                                                            |
| Incremental operation | Persist compatible derived repository facts and optional candidate-index data, with explicit invalidation and rebuild behavior.                                                                        |
| Reports               | Add a separately versioned R2 evidence report or sidecar. Do not mutate syntax-only report schemas 2.                                                                                                  |
| Platforms             | Preserve current SwiftDebt deployment targets and Linux buildability. SQVector-backed similarity may be available only on its qualified platform intersection and must report unavailable elsewhere.   |

R2 may ship only when both named repository-aware smells meet the Supported
gates in this PRD. Feature Envy, Middle Man, and Alternative Classes with
Different Interfaces ship with a Research state unless they independently meet
every Supported gate and receive an explicit release-scope revision.

---

## Evidence and Truth Model

### Evidence classes

| Class           | Examples                                                                   | What it may establish                                                        |
| --------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Syntax          | Declarations, expressions, access chains, control-flow shape               | Facts present in parsed source under the documented syntax-only contract     |
| Metric          | Parameter count, body size, foreign-to-local access ratio                  | A threshold predicate when the measurement and denominator are complete      |
| Structural      | Normalized signatures, repeated declaration groups, repeated switch shapes | Repository patterns under a versioned normalization contract                 |
| Relationship    | Owns, references, reads, writes, calls, forwards, accepts, returns         | Cross-unit predicates at the capability level that produced the edge         |
| Compiler-backed | Name binding, resolved ownership, conformance, dispatch candidates         | Semantic facts only when the matching sidecar marks the capability available |
| Similarity      | Lexical, structural-vector, relationship-vector, or embedding proximity    | Candidate priority only                                                      |

Historical evidence is reserved for a later release. R2 does not use commit
history to claim Divergent Change or Shotgun Surgery.

### Capability outcomes

- `available`: the named provider produced evidence for the declared scope. An
  exact capability may contribute to a positive or negative predicate.
- `unavailable`: the capability did not produce usable evidence and records a
  machine-readable reason. It cannot contribute to an absence claim.
- `ambiguous`: evidence cannot identify one semantic result and records the
  competing state or reason. A rule cannot choose a candidate silently.
- `failed`: execution did not commit. Any result that depends on it is
  incomplete.
- `approximate`: retrieval can omit neighbors. It may propose candidates but
  cannot prove that no qualifying candidate exists.

### Detection completeness

A repository-aware rule proves absence only when every required capability is
available, every required analysis unit in the declared scope commits, and the
rule's candidate enumeration is exact. A rule that uses approximate retrieval
must either run an exact completeness path before claiming absence or report
the rule outcome as incomplete for absence purposes.

A positive candidate becomes a Detection only after a deterministic,
rule-specific predicate validates sufficient evidence. The report must retain
the candidate mechanism as provenance without making it the reason for the
Detection.

---

## Functional Requirements

### Repository evidence foundation

- **FR-1 - R1 preservation:** R2 shall run existing syntax-only rules through
  the R1 atomic rule and `SourceUnit` contract without changing their
  Detections or absence semantics.
- **FR-2 - Snapshot identity:** Every repository analysis shall identify the
  selected source scope, normalized paths, content digest, configuration,
  SwiftDebt version, rule revisions, and, when available, version-control
  revision and working-tree state.
- **FR-3 - Repository units:** R2 shall represent files, nominal types,
  extensions, functions, methods, initializers, properties, and closures as
  analysis units with source locations and parent ownership. Anonymous or
  synthesized units shall expose their stability limits.
- **FR-4 - Deterministic facts:** R2 shall derive versioned syntax, metric,
  structural, and relationship facts with deterministic ordering from identical
  inputs.
- **FR-5 - Relationship vocabulary:** R2 shall support the relationships needed
  by committed rules, including ownership, reference, read, write, call,
  forwarding, parameter, return, construction, extension, inheritance, and
  conformance. Every relationship shall identify its evidence class and
  capability state.
- **FR-6 - Compiler evidence boundary:** Compiler-backed relationships shall be
  accepted only from a compatible compiler-evidence sidecar whose source
  identity and configuration match the analyzed snapshot. Mismatch shall be
  explicit and unusable.
- **FR-7 - Capability declaration:** Each rule shall declare required and
  optional capabilities before execution. Selecting syntax-only rules shall not
  initialize compiler, embedding, vector-index, or repository-history services.
- **FR-8 - Bounded execution:** Repository analysis shall enforce declared work,
  memory, candidate-count, and input-size budgets. Exhaustion shall fail or mark
  the affected rule incomplete; it shall not return a clean result.

### Fowler catalog and rule behavior

- **FR-9 - Complete catalog:** R2 shall contain one machine-readable entry for
  each of the 24 second-edition Fowler smell names.
- **FR-10 - Support state:** Every catalog entry shall be exactly one of
  `Supported`, `Partially Supported`, `Research`, or `Not Reliably Observable`,
  with the state defined in the report schema.
- **FR-11 - Coverage contract:** Every entry shall record its rule identity when
  one exists, semantic revision, minimum predicate, required and optional
  evidence, scope, known false-positive and false-negative risks, explanation
  contract, and fixture references.
- **FR-12 - R2 graduation set:** Data Clumps and Repeated Switches shall meet all
  Supported gates before R2 release. Feature Envy and Middle Man shall remain
  Research until a compatible compiler provider supplies complete ownership and
  binding evidence; syntax-only approximations may not graduate them.
- **FR-13 - Concrete location:** Every Detection shall identify a present source
  span that a developer can inspect. A repository-level aggregate without a
  concrete primary location is not a Detection.
- **FR-14 - Explanation:** Every Detection shall explain the decisive observed
  facts, predicate or threshold, relevant compared units, evidence classes, and
  a specific refactoring direction. It shall link to the rule's published
  Swift-specific DocC article. A bare label or score is insufficient.
- **FR-15 - Honest absence:** A rule shall expose incomplete or unsupported
  scope when required evidence is unavailable, ambiguous, failed, approximate,
  or outside the selected source set.
- **FR-16 - Advisory default:** New R2 Detections shall remain advisory unless
  the user explicitly enables a policy gate for the rule and support state.

### Optional hybrid similarity

- **FR-17 - Opt-in activation:** Similarity analysis shall be disabled by
  default. Enabling it shall be explicit in configuration or the CLI.
- **FR-18 - Candidate-only semantics:** Lexical, structural, relationship, and
  semantic similarity shall return bounded candidate sets. No similarity
  threshold or nearest-neighbor result shall emit a Detection directly.
- **FR-19 - Deterministic projection:** Semantic embedding input shall be a
  versioned, formatting-independent projection of a repository unit. Raw source
  text shall not be the canonical projection.
- **FR-20 - Provider isolation:** Rules shall depend on a SwiftDebt similarity
  capability, not on NaturalLanguage, SQVector, SQLite, an embedding SDK, or an
  ANN implementation.
- **FR-21 - Provider identity:** An embedding result shall record provider name,
  provider implementation version, model or vocabulary identity when exposed,
  operating-system or framework version when relevant, vector dimensions,
  normalization, distance metric, projection revision, and source projection
  digest. Unexposed model identity shall be recorded as unavailable, not
  invented.
- **FR-22 - Candidate-index identity:** A similarity result shall record index
  provider, exact package version and source revision, index schema version,
  exact or approximate capability, algorithm and material parameters,
  namespace, filter behavior, and distance metric.
- **FR-23 - SQVector selection:** SQVector from
  `https://github.com/brunogama/sqvector-swift` is the selected optional local
  candidate index. R2 shall consume only a qualified, exact revision through the
  nested package's `SQVectorStatic` SwiftPM product and an R2-owned adapter. The
  imported module remains `SQVector`, and the existing automatic library
  product shall remain available for other consumers.
- **FR-24 - Index capability:** The candidate index shall support insert,
  replacement, deletion, persistence, dimension validation, provider and model
  namespaces, bounded nearest-neighbor retrieval, and metadata filtering needed
  to isolate compatible repository units.
- **FR-25 - Compatibility rejection:** R2 shall reject or rebuild index data
  when projection revision, provider identity, model identity, vector
  dimensions, metric, index schema, source snapshot, or package compatibility
  does not match.
- **FR-26 - Local privacy default:** R2 shall create projections, embeddings,
  and candidate indexes locally by default. It shall make no network request,
  load no remote embedding provider, and transmit no source, projection,
  identifier, vector, metadata, or telemetry unless a future, separately scoped
  capability explicitly changes that contract.

### Incremental derived state

- **FR-27 - Content-addressed reuse:** R2 shall reuse derived facts only when
  source content, analysis compatibility, rule semantics, projection revision,
  provider identity, and relevant configuration remain compatible.
- **FR-28 - Precise invalidation:** A source change shall invalidate the changed
  units and every dependent fact required by affected rules. The run shall
  report invalidation counts and reasons.
- **FR-29 - No stale fallback:** Cache corruption, partial writes, schema
  mismatch, or interrupted migration shall trigger an atomic rebuild or an
  incomplete run. R2 shall never use stale derived state silently.
- **FR-30 - Atomic persistence:** Index and fact updates shall not expose a
  mixed snapshot after interruption. A successful run shall reference one
  coherent source and provider identity.
- **FR-31 - Inspectable storage:** Documentation and diagnostics shall identify
  cache location, retained data classes, size, compatibility identity, and a
  deterministic way to clear and rebuild derived state.

### Product surfaces and reporting

- **FR-32 - Consistent surfaces:** The library, standalone CLI, command plugin,
  and build plugin shall use the same rule semantics and completeness model for
  capabilities each surface can support.
- **FR-33 - Progressive output:** Default human output shall show rule, primary
  location, concise explanation, decisive evidence, and incomplete capability
  notices. Detailed output shall expose compared units, normalized facts,
  candidate provenance, and provider identity.
- **FR-34 - Versioned machine report:** Repository evidence shall use a new,
  separately versioned report or sidecar. It shall not alter `AnalysisReport`
  schema 2, `DebtReport` schema 2, or the compiler-evidence sidecar schema by
  implication.
- **FR-35 - Current-snapshot semantics:** Reports shall state that Detections
  describe the analyzed snapshot. They shall not expose open, fixed, reopened,
  age, owner, suppression-history, or resolution fields.
- **FR-36 - Stable ordering:** Human and machine outputs shall sort
  deterministically independent of parse concurrency, candidate retrieval
  completion order, or filesystem enumeration.
- **FR-37 - Configuration validation:** Unknown rule states, capabilities,
  providers, metrics, projection revisions, or threshold keys shall fail with an
  actionable diagnostic rather than fall back silently.
- **FR-38 - Explainability API:** Library and CLI consumers shall be able to
  request the full evidence explanation for a current Detection using its rule,
  semantic revision, source snapshot, and location selector. This selector is
  not a durable Finding identifier.

---

## Non-Functional Requirements

- **NFR-1 - Determinism:** Identical inputs and exact providers shall produce
  byte-identical machine evidence after excluding explicitly non-contractual
  benchmark timing data.
- **NFR-2 - Reproducibility:** Every result shall carry enough source, rule,
  configuration, provider, projection, and index provenance to determine
  whether two runs are comparable.
- **NFR-3 - Privacy:** A hermetic run with default configuration shall complete
  without network access and shall record no telemetry.
- **NFR-4 - Concurrency safety:** Public R2 APIs and adapters shall satisfy Swift
  6 complete concurrency checking and preserve deterministic commit order.
- **NFR-5 - Platform compatibility:** R2 shall preserve macOS 13, iOS and iPadOS
  16, tvOS 16, watchOS 9, visionOS 1, and the existing Linux build surface.
  Optional SQVector capability shall be compiled only where its qualified static
  product supports the target.
- **NFR-6 - Dependency containment:** Consumers that do not select similarity
  shall not have to depend on `SQVectorStatic`, embedding providers, or
  remote-provider SDKs. Similarity-disabled execution shall initialize none of
  those capabilities and shall open no vector store.
- **NFR-7 - Recoverability:** Derived state shall be disposable. Deleting it and
  rerunning against the same compatible inputs shall reconstruct equivalent
  facts and exact-provider results.
- **NFR-8 - Documentation:** Every Supported or Partially Supported smell shall
  have published Swift-specific documentation describing its evidence,
  limitations, examples, and suggested refactoring direction. Its stable article
  link shall appear in each Detection for that smell.

---

## Fowler R2 Coverage Contract

The table defines the R2 release state, not the eventual product ceiling.
`Supported` is earned only after all release gates pass.

| Fowler smell                                  | R2 state                | Release provenance | Minimum evidence contract                                                                       |
| --------------------------------------------- | ----------------------- | ------------------ | ----------------------------------------------------------------------------------------------- |
| Mysterious Name                               | Not Reliably Observable | Deferred           | Repository naming intent or a narrowly defined placeholder-name contract                        |
| Duplicated Code                               | Research                | R2                 | Normalized bodies with meaningful equivalence and concrete duplicate spans                      |
| Long Function                                 | Supported               | R1                 | Function body size above a documented threshold                                                 |
| Long Parameter List                           | Supported               | R1                 | Declared parameter count above a documented threshold                                           |
| Global Data                                   | Supported               | R1                 | Mutable top-level declaration under the documented syntax scope                                 |
| Mutable Data                                  | Research                | R2                 | Mutation, aliasing, ownership, and lifetime evidence                                            |
| Divergent Change                              | Research                | Deferred           | Distinct reasons for edits over version-control history                                         |
| Shotgun Surgery                               | Research                | Deferred           | Coordinated edits across files over version-control history                                     |
| Feature Envy                                  | Research                | R2                 | Compiler-backed member ownership plus a documented foreign-to-local access predicate            |
| Data Clumps                                   | Supported               | R2                 | Repeated, type-compatible parameter or property groups across repository units                  |
| Primitive Obsession                           | Not Reliably Observable | Deferred           | Domain meaning that distinguishes a primitive from an appropriate value type                    |
| Repeated Switches                             | Supported               | R2                 | Repeated normalized dispatch structures over the same resolved or exact syntactic discriminator |
| Loops                                         | Not Reliably Observable | Deferred           | Evidence that a specific transformation improves clarity, beyond loop presence                  |
| Lazy Element                                  | Research                | R2                 | Role and actual use of a small abstraction across the repository                                |
| Speculative Generality                        | Research                | R2                 | Unused extension points plus evidence about intended variation                                  |
| Temporary Field                               | Research                | R2                 | State usage limited to a documented object-lifetime phase                                       |
| Message Chains                                | Research                | R2                 | Resolved access graph and an actionable delegation boundary                                     |
| Middle Man                                    | Research                | R2                 | Compiler-backed ownership and forwarding behavior above a documented delegation predicate       |
| Insider Trading                               | Research                | R2                 | Resolved cross-type access, visibility, ownership, and collaboration evidence                   |
| Large Class                                   | Supported               | R1                 | Type body size above a documented threshold                                                     |
| Alternative Classes with Different Interfaces | Research                | R2                 | Role-equivalent candidate pair plus deterministic API and behavior validation                   |
| Data Class                                    | Research                | R2                 | Data ownership, behavior placement, and externally owned behavior                               |
| Refused Bequest                               | Research                | R2                 | Inheritance contract plus evidence that inherited behavior is unused or inappropriate           |
| Comments                                      | Not Reliably Observable | Deferred           | Evidence that a comment compensates for unclear behavior rather than documenting intent         |

No documentation, CLI, or report may summarize Research, Partially Supported,
or Not Reliably Observable entries as fully covered.

---

## Success Metrics and Release Gates

### Labeled-corpus gate

Each newly Supported rule shall be evaluated on a frozen, reviewable corpus with:

- at least 30 positive cases and 60 adversarial negative cases;
- at least three distinct repository shapes and two real-world repository
  snapshots where licensing permits redistribution or reproducible checkout;
- labels independently reviewed by two qualified Swift reviewers, with
  disagreements adjudicated and recorded;
- precision of at least 0.90;
- false-positive rate of at most 0.05;
- recall of at least 0.80 for the rule's explicitly declared observable scope;
  and
- no result counted as a true negative when a required capability is
  unavailable, ambiguous, approximate without an exact fallback, or failed.

The corpus report shall publish the confusion matrix, scope exclusions, known
false positives, known false negatives, rule semantic revision, and source
identity. Aggregate accuracy without per-rule results does not pass.

### Explanation gate

- 100 percent of Detections include a concrete source location, decisive facts,
  rule predicate, evidence classes, capability state, refactoring direction,
  and a working link to the rule's published Swift-specific DocC article.
- Zero Detections use a similarity score as their sole decisive evidence.
- Zero clean rule outcomes are produced from missing, failed, ambiguous, or
  approximate-only required evidence.

### Similarity and index gate

On the frozen candidate corpus declared by the release benchmark manifest:

- approximate recall at the configured candidate limit is at least 0.95 against
  exact nearest-neighbor results for the same metric and filters;
- p95 nearest-neighbor latency, peak RSS, index size, and maximum candidate count
  stay within the calibrated release budget described below;
- the corpus includes the largest intended R2 reference repository plus the
  synthetic scale points needed to expose candidate growth;
- dimension, namespace, provider, model, metric, and projection mismatches are
  rejected in every compatibility fixture; and
- hybrid retrieval is retained only if it improves recall for the measured
  research task without reducing precision by more than one percentage point
  relative to the best deterministic baseline.

If SQVector cannot meet these gates as a static, local, version-qualified
candidate index, R2 does not pass its hybrid and index commitment. Deterministic
repository rules may be released separately, but they do not constitute the
complete R2 release defined by this PRD.

### Determinism and incremental gate

- Ten repeated clean runs at parse-job counts 1, 2, and 8 produce identical
  machine evidence for exact providers.
- An unchanged warm run reprojects and re-embeds zero units.
- A one-file edit reprocesses only the changed units and the dependency closure
  declared by affected rules; fixtures assert the exact invalidation set.
- Interrupted writes and corrupted cache fixtures either rebuild atomically or
  make the run incomplete.
- A cache-free rerun reconstructs evidence equivalent to the compatible warm
  result.

### Performance gate

Before implementation freeze, the team shall check in a versioned release
benchmark manifest and calibrated budget artifact. The manifest fixes the source
snapshots, analysis-unit counts, configuration, toolchain, operating system,
hardware class, provider identities, cold or warm state, and measured stages.
The artifact records median, p95, peak RSS, index size, candidate count, and the
approved limit for every scenario.

Calibration shall run five unmeasured warmups followed by at least 30 measured
runs of the R1 baseline and applicable R2 prototype on the same environment.
For a stage whose baseline p95 is under one second, a ratio alone shall not fail
the gate. Each scenario shall record its own absolute millisecond noise floor,
derived by default from three median absolute deviations. The floor may exceed
the relative threshold for a noisy short workload; there is no universal cap.
A short-stage regression fails only when it breaches both the approved relative
limit and its calibrated absolute floor. The artifact shall publish the raw
samples, declare the scenario-specific maximum tolerated absolute regression,
and demonstrate that a deliberate workload increase above that boundary makes
the gate fail. A scenario too noisy to detect that regression is not a valid release
benchmark. Longer-stage and memory limits shall be approved from the frozen
measurements before implementation freeze, rather than invented after a
regression appears.

Release performance passes when:

- similarity-disabled cold wall time and peak RSS stay within their approved R1
  relative budgets on every frozen workload;
- unchanged warm and standard one-file edit scenarios each stay within their
  own approved absolute budgets and do not re-embed unchanged units;
- no budget is calculated from the number of changed lines or units;
- similarity-disabled execution initializes zero embedding providers, performs
  zero candidate-index operations, and creates zero vector-index files; and
- performance-budget exhaustion produces an incomplete result and a
  machine-readable reason.

The calibrated artifact turns these procedures into exact release gates. A
regression waiver shall identify the affected metric, measured evidence, owner,
and expiry release.

---

## Acceptance Criteria

R2 is accepted when all of the following are demonstrated through the real
library and CLI surfaces:

1. Existing R1 rule fixtures and end-to-end CLI behavior pass unchanged,
   including advisory default, explicit failure gate, and incomplete-analysis
   semantics.
2. A separately versioned R2 evidence artifact identifies source snapshot,
   rules, capabilities, facts, completeness, and provider provenance without
   changing syntax-only report schemas 2.
3. The machine-readable catalog contains all 24 Fowler entries and matches the
   published human coverage table.
4. Data Clumps and Repeated Switches each pass the labeled-corpus, explanation,
   determinism, and performance gates. Their real CLI Detections link to their
   published Swift-specific DocC articles.
5. Feature Envy and Middle Man remain Research and produce no support claim. Any
   exposed research result reports incomplete or unsupported when compatible
   compiler-backed binding and ownership evidence is absent; it never falls
   back to an unlabeled syntax guess.
6. An approximate or semantic neighbor can become a Detection only after the
   rule's deterministic validation predicate passes.
7. A no-neighbor result from ANN does not prove absence unless an exact
   completeness path also commits.
8. The default configuration completes in a network-denied environment and
   transmits no source or derived data.
9. Similarity-disabled runs perform no embedding or SQVector work and preserve
   SwiftDebt's current platform and Linux build surfaces.
10. The selected SQVector revision exposes `SQVectorStatic`, builds it as a
    static SwiftPM library for every enabled integration platform, is pinned
    exactly, and passes insert, replacement, deletion, persistence, filtering,
    dimension, namespace, and retrieval contract tests through the SwiftDebt
    adapter.
11. Evidence records expose embedding-provider, projection, vector-index,
    capability, and exact version provenance. Unavailable provider version data
    remains explicitly unavailable.
12. Cache invalidation, corruption recovery, cold rebuild, unchanged warm run,
    and one-file edit scenarios pass with the declared recomputation evidence.
13. Human output and machine output explain every Detection without implying a
    durable Finding or lifecycle state.
14. Benchmark and accuracy evidence is checked into a reviewable release record
    and every frozen accuracy and performance budget passes.

---

## Non-Goals

R2 does not include:

- Detection reconciliation across runs;
- durable Finding identifiers or open, resolved, reopened, suppressed, age, or
  ownership states;
- Git-history detection of Divergent Change or Shotgun Surgery;
- cloud LLM analysis, repository chat, or remediation generation;
- automatic source modification or refactoring;
- mandatory embeddings, a mandatory model download, or a remote inference
  service;
- similarity as a quality score, confidence percentage, or proof of debt;
- full support claims for all 24 Fowler smells;
- source transmission, telemetry, or remote embedding-provider activation;
- an IDE graphical interface;
- replacement of SwiftDebt's compiler-evidence sidecar; or
- changes to `AnalysisReport` schema 2 or `DebtReport` schema 2.

---

## Risks and Mitigations

| Risk                                                         | Product consequence                     | Required mitigation                                                                                               |
| ------------------------------------------------------------ | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Syntax relationships are mistaken for resolved semantics     | False Feature Envy or Middle Man claims | Require compatible compiler-backed ownership and binding capabilities for Supported state.                        |
| ANN misses a relevant neighbor                               | False absence                           | Treat ANN as candidate-only and require an exact path before proving absence.                                     |
| Generic embeddings group vocabulary rather than behavior     | Noisy candidates                        | Compare against lexical, structural, and relationship baselines; keep semantic mode opt-in.                       |
| Apple embedding identity changes across OS versions          | Non-comparable vectors                  | Record exposed provider and OS identity, namespace indexes, and report unexposed model identity as unavailable.   |
| SQVector raises platform or dependency requirements          | Existing consumers cannot build         | Use an optional static product and adapter on the qualified platform intersection; preserve base package targets. |
| SQVector facade pulls remote providers or unrelated features | Privacy and binary-size regression      | Qualify a minimal local-index static slice and verify the resolved dependency graph.                              |
| Stale incremental state changes a result                     | Untrustworthy analysis                  | Content-address compatibility, atomic updates, exact invalidation fixtures, and disposable rebuilds.              |
| Fowler labels imply subjective certainty                     | User over-trust                         | Publish minimum predicates, observable scope, support states, blind spots, and corpus metrics per rule.           |

---

## Open Product Decisions

The following decisions do not change the R2 truth model, but must be closed
before implementation freeze:

1. Which separately versioned report name and schema carry repository evidence?
2. Which compiler provider first supplies compatible ownership and name-binding
   evidence for Feature Envy and Middle Man?
3. Which deterministic semantic projection provides the best retrieval value
   without retaining unnecessary source text?
4. Which local embedding provider can expose sufficient identity for meaningful
   cache compatibility on each supported platform?
5. Which exact SQVector revision and minimal static product pass the qualification
   gates without raising SwiftDebt's base deployment targets?
6. Should the R2 similarity experiment remain macOS-only if no qualified provider
   exists across the broader Apple-platform matrix?
7. What report selector syntax gives users a convenient explanation lookup while
   making clear that it is not a durable Finding ID?

An unresolved item blocks release only when it prevents an acceptance criterion
from being tested or satisfied.

---

## Technical Addendum (Non-Normative)

This addendum preserves design ideas from the initial draft. It guides
architecture work but does not override the product requirements above.

### Candidate pipeline

```text
Selected Swift source
        |
        v
R1 parse and atomic rule/source outcomes
        |
        v
Versioned repository units and exact facts
        |                                  \
        |                                   \ optional, opt-in
        v                                    v
Deterministic predicates             Semantic projection
        |                                    |
        |                                    v
        |                             Local embedding provider
        |                                    |
        |                                    v
        |                             SQVector static index
        |                                    |
        |                                    v
        |                              Bounded candidates
        |                                    |
        +----------------+-------------------+
                         |
                         v
              Rule-specific validation
                         |
                         v
             Detection plus evidence record
```

The pipeline ends at current-snapshot Detection. It has no reconciliation or
lifecycle stage.

### SQVector qualification note

SQVector is selected because its published surface is designed for local,
in-process vector persistence and retrieval, with exact search, ANN options,
metadata-aware querying, and SQLite-backed storage. Selection does not equal
qualification.

At PRD preparation time, the available local checkout had origin
`https://github.com/brunogama/sqvector-swift.git`, included a `v1.0.0` tag, and
contained development beyond that tag. The intended integration change adds an
explicit `SQVectorStatic` product to the nested `Packages/SQVector` manifest,
backed by the existing `SQVector` module, while preserving its automatic
`SQVector` product. R2 still requires an exact clean revision plus compilation
and pull-request verification before integration; this PRD does not claim that
the static product is already published.

The preferred qualification slice contains only the storage and candidate-index
capabilities required by FR-24. Remote embedding providers, CloudKit sync,
document ingestion, macros, command-line tools, and unrelated retrieval features
should not enter SwiftDebt's dependency graph unless a demonstrated requirement
needs them.

### Semantic projection experiment

Candidate projection schemas should be compared on retrieval quality,
formatting stability, identifier sensitivity, size, construction time, and
privacy. Useful fields may include unit kind, normalized signature, owned and
foreign access patterns, call-shape summary, relationship features, and selected
identifiers. Formatting trivia and raw full-file text should be excluded.

### Required experiments

1. Compare lexical, normalized structural, relationship-vector, local embedding,
   and hybrid retrieval on the same labeled candidate corpus.
2. Compare exact retrieval with each SQVector approximate strategy at fixed
   recall targets and candidate budgets.
3. Mutate method, type, extension, and file boundaries and assert the exact
   derived-state invalidation set.
4. Run provider and projection compatibility fixtures across supported OS and
   toolchain versions.
5. Measure static artifact size, transitive dependency graph, startup cost, warm
   reuse, and unsupported-platform behavior.
6. Run all default analysis in a network-denied harness and inspect attempted
   connections and persisted data classes.

### Future release candidates

Git-history evidence for Divergent Change and Shotgun Surgery, richer
architectural drift analysis, durable Finding reconciliation, baselines,
resolution state, and agent-oriented remediation belong in later PRDs. Their
future data models must not be inferred from R2's current Detection selector or
candidate-index identity.
