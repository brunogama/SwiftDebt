# SwiftDebt R3 --- Repository Intelligence & Evidence Graph

**Status:** Draft\
**Release:** R3\
**Created:** 2026-09-24\
**Predecessors:** R1 Trustworthy Observation; R2 Hybrid Code-Smell
Analysis\
**Theme:** Repository-wide structural intelligence, evidence reuse,
graph-native analysis, and capability-driven execution.

## 0. Document Purpose

SwiftDebt R3 evolves the product from increasingly capable
static-analysis rules into a repository-intelligence platform. R1
established trustworthy observations and lifecycle authority, while R2
added hybrid code-smell detection using syntax, metrics, relationships,
and selective semantic similarity. R3 makes repository topology a
first-class analysis surface so rules no longer rediscover the same
relationships independently. It introduces a typed `RepositoryGraph`, a
distinct `EvidenceGraph`, reusable indexes, temporal relationships,
graph queries, hotspot evidence, architectural-community analysis, and a
capability-driven query planner. The goal is not to maximize rule count,
but to build the substrate that makes future architectural, historical,
and remediation-oriented rules fast, consistent, incremental, and
explainable.

# 1. Define the Basics

R3 builds the **Repository Intelligence Engine** for SwiftDebt. Its
elevator pitch is: **SwiftDebt R3 understands how a Swift repository is
connected, computes reusable architectural and historical evidence once,
and lets debt rules query that evidence without repeatedly paying
repository-analysis costs.** Source, symbols, references, optional Git
history, structural vectors, and semantic indexes are normalized into
typed repository evidence rather than exposed as unrelated subsystems.
Vector search becomes one index among several rather than the center of
the architecture, and no LLM is required. The product remains
local-first and should feel like compiler-grade infrastructure hidden
behind `swift-debt analyze .`, not like a graph-database product.

Conceptual team ownership is divided among Product/Rule Semantics, Swift
Static Analysis, Repository Intelligence/Search, and Developer
Experience. Product owns evidence semantics and acceptance; Static
Analysis owns extraction and symbol relationships; Repository
Intelligence owns graphs, indexes, algorithms, and planning; DX owns
CLI, reports, diagnostics, and machine-readable schemas. These roles may
initially be held by one maintainer, but the boundaries must remain
explicit. Stakeholders include Swift developers, staff/principal
engineers, architecture teams, CI/platform engineers, maintainers of
large repositories, rule authors, and future automated consumers. Agents
are secondary consumers in R3 and are not allowed to modify source as
part of this release.

R3 has no fixed calendar date in this PRD. It ships when graph
correctness, incremental invalidation, explainability, query
determinism, and performance gates pass. The current status is
**discovery / architecture definition**, with R2 stabilization as the
primary prerequisite. Major risks are graph identity, invalidation
radius, cross-file symbol resolution, Git normalization, and scope
inflation into a generic code-intelligence system. These are not
blockers to design, but each requires an implementation spike before
schedule estimates are credible.

``` mermaid
flowchart LR
    R1[R1: Trustworthy Observation] --> R2[R2: Hybrid Smell Analysis]
    R2 --> R3[R3: Repository Intelligence]
    R3 --> R4[R4: Evolution Intelligence]
    R3 --> R5[R5: Architecture Conformance]
```

# 2. Capture Strategy

The primary objective is to compute repository-wide relationships once
and make them reusable by many rules and features. This eliminates
duplicated traversal work, creates one definition for concepts such as
ownership, caller, dependency, and temporal coupling, and lets SwiftDebt
reason about topology rather than isolated syntax. Expensive
capabilities must remain lazy so syntax-only rule sets do not pay for
Git, semantic indexes, or graph algorithms they never use. Derived
evidence must remain traceable to concrete source/history facts. Success
means analysis power grows faster than analysis cost as the rule catalog
expands.

The expected value is lower marginal cost for future rules and
substantially more consistent evidence. Feature Envy, cycle detection,
hotspot analysis, and architecture rules should consume the same
reference/call/ownership indexes instead of independently reconstructing
them. Historical evidence can reveal temporal coupling and change
hotspots that cannot be observed from the current source snapshot.
Structural communities can expose disagreement between physical module
boundaries and actual dependency clusters. These capabilities create a
foundation for later architecture, evolution, remediation, and
agent-facing releases without prematurely implementing those products.

R3 supports SwiftDebt's broader goal of representing technical debt as
executable, inspectable claims rather than vague comments or opaque
quality scores. Repository topology and temporal coupling differentiate
SwiftDebt from conventional local linters, while local execution and
bounded planning reduce adoption and privacy friction. The strategic
rules are: compute once/reuse broadly; prefer typed facts over generic
graph blobs; preserve provenance; make expensive capabilities lazy; and
optimize incremental behavior before adding many new rules. A generic
graph database is explicitly not the product goal. Semantic/vector
evidence remains complementary to structural evidence rather than
replacing it.

``` mermaid
flowchart TD
    Source[Swift Source] --> Extract[Shared Extraction]
    Extract --> Syntax[Syntax Index]
    Extract --> Symbols[Symbol Index]
    Extract --> Refs[Reference Index]
    Extract --> Calls[Call Graph]
    Extract --> Deps[Dependency Graph]
    Git[Git History] --> Change[Change Index]
    Syntax --> Evidence[Evidence Graph]
    Symbols --> Evidence
    Refs --> Evidence
    Calls --> Evidence
    Deps --> Evidence
    Change --> Evidence
    Evidence --> Rules[Debt Rules]
```

# 3. Offer Context

R1 deliberately kept rules close to trustworthy current-source
observations, and R2 introduced richer evidence without making
embeddings authoritative. As smells become cross-file and relational,
repeated per-rule traversal becomes both a performance and consistency
problem. Two rules should not disagree about who owns a method, which
symbols it references, or whether modules form a dependency cycle
because they implemented extraction differently. R3 centralizes those
facts and their provenance while leaving rule semantics independent.
This is the point where SwiftDebt moves from "rules plus helpers" into a
coherent repository-intelligence substrate.

The release is informed by the evidence requirements of harder smells:
Feature Envy needs ownership/reference affinity, Shotgun Surgery needs
change relationships, Divergent Change needs historical responsibility
patterns, and architectural smells need topology. It is also informed by
the requirement that semantic/vector analysis be selective rather than
universal. No customer-interview dataset is assumed by this PRD, so
product claims must be validated with representative Swift repositories,
curated fixtures, and maintainer feedback rather than invented research.
False-positive examples and performance traces should feed the test
corpus. Mandatory telemetry is not required.

Target personas are senior Swift developers, staff/principal engineers,
CI/platform engineers, and SwiftDebt rule authors. A developer wants one
command and useful explanations; a staff engineer wants coupling,
cycles, hotspots, and architectural evidence; CI needs stable runtime
and explicit incompleteness; rule authors need reusable bounded queries.
Typical use cases include repository analysis, changed-code analysis,
explaining a hotspot or cycle, and implementing a custom rule without
rebuilding graph logic. R3 also prepares for R4 Evolution Intelligence
and later architecture conformance, remediation, and agent APIs, but
those future goals must not force premature public APIs now.

# 4. List Assumptions

R3 assumes R2 can provide stable-enough SemanticUnit identity within an
analysis snapshot while long-term Finding identity remains owned by R1
lifecycle logic. It assumes most useful repository relationships can be
derived from SwiftSyntax plus available symbol-resolution facilities
without reimplementing the Swift compiler. It assumes typed
adjacency/index structures will outperform a generic property graph for
SwiftDebt's actual query set. It also assumes Git history can be
normalized sufficiently for useful co-change evidence despite renames,
merges, generated files, and noisy commits. Every assumption must be
validated by an implementation spike before becoming a frozen
architectural constraint.

The performance hypothesis is that graph construction can be incremental
and a one-file edit usually affects a bounded neighborhood. Persisted
indexes should carry compatibility metadata and reopen cheaply between
runs. Query planning should avoid history, semantic, and expensive
reverse indexes when enabled rules do not request them. Graph algorithms
such as strongly connected components should be scoped or cached rather
than blindly recomputed after every local edit. If these assumptions
fail, feature scope must be reduced before accepting unbounded runtime.

Product assumptions are equally explicit. Users are assumed to value
explanations more than a single composite "architecture score," and
repository topology is assumed to be useful even when SwiftDebt does not
prescribe a fix. Explicit unknown/incomplete states are assumed
preferable to confident-looking guesses. Rule authors are assumed to
benefit from capability-driven APIs enough to justify a planner. Users
are assumed not to want to configure Neo4j, a server, or a cloud service
merely to analyze a Swift package.

R3 assumes a small maintainer team, so subsystem count and operational
dependencies must remain bounded. New subsystems require strong
automated tests because manual regression testing will not scale.
Performance benchmarking must be repeatable in CI or a dedicated
benchmark harness. The release should prefer a small number of
representative graph-powered rules over broad shallow rule coverage.
Documentation should be generated from capability/rule metadata where
practical to reduce drift.

If symbol resolution proves incomplete, affected relationships must
carry completeness metadata or be scoped down. If Git normalization is
unreliable, historical rules remain opt-in or partial instead of
contaminating deterministic current-source analysis. If persistent graph
storage adds more complexity than value, R3 should persist specialized
indexes rather than a monolithic graph. If community or centrality
metrics are difficult to explain, they remain research evidence rather
than production findings. These fallback positions are intentional
safeguards against architecture driven by attractive algorithms rather
than observable product value.

# 5. Detail Requirements

## 5.1 Typed RepositoryGraph --- P0

R3 must introduce a typed `RepositoryGraph` representing code entities
and relationships relevant to SwiftDebt. Node kinds include at minimum
package/target/module where observable, file, type, protocol, extension,
function/method, initializer, property, and useful external
dependencies. Edge kinds include ownership, calls, reads, writes,
references, inheritance, conformance, construction, imports, and
dependency relationships. Every node and edge retains enough provenance
to map graph facts back to source units or external evidence. The
primary API must not degrade into an untyped property-bag model.

## 5.2 Repository Indexes --- P0

The engine must expose shared indexes for syntax facts, symbols,
references, calls, dependencies, and reverse relationships. Indexes are
built only when demanded by active capabilities or cheap prerequisites.
Every persistent index has compatibility/version metadata so reuse and
invalidation are safe. Rules consume interfaces rather than storage
implementations. Multiple rules requesting the same capability share one
computed index per analysis snapshot.

## 5.3 EvidenceGraph --- P0

R3 introduces an `EvidenceGraph` distinct from the RepositoryGraph. The
RepositoryGraph describes observed code relationships; the EvidenceGraph
describes derived claims used by rules. A method may have raw `reads`
edges while the EvidenceGraph contains a derived `foreignOwnerAffinity`
backed by those reads. Derived evidence records inputs,
algorithm/revision, scope, and completeness. This separation prevents
heuristics from being mistaken for raw repository truth.

## 5.4 Capability-Driven Query Planner --- P0

Rules declare analysis capabilities and the engine computes the minimal
execution plan for the enabled rule set. The planner understands
prerequisites such as `temporalCoupling → changeIndex → gitHistory` and
`foreignOwnerAffinity → references + ownership`. It deduplicates shared
prerequisites and avoids unrelated expensive systems.
Diagnostic/benchmark mode exposes the plan so users can see why a stage
ran. Planning must be deterministic for the same
rule/configuration/capability set.

``` mermaid
flowchart TD
    Rules[Enabled Rules] --> Req[Capability Requirements]
    Req --> Planner[Query Planner]
    Planner --> Syntax[Syntax]
    Planner --> Symbols[Symbols]
    Planner --> Calls[Call Graph]
    Planner --> Hist[History]
    Planner --> Sem[Semantic Index]
    Syntax --> Shared[Shared Evidence]
    Symbols --> Shared
    Calls --> Shared
    Hist --> Shared
    Sem --> Shared
    Shared --> Rules
```

## 5.5 Graph Query API --- P0

R3 provides bounded typed queries for dependencies, dependents, callers,
callees, referenced owners, transitive dependencies, relevant shortest
paths, strongly connected components, and connected components. Queries
define whether they are snapshot-local, repository-global, or
scope-filtered. Potentially unbounded traversals require explicit limits
or scoped variants. Results should use stable ordering where practical
for deterministic reports and tests. Query results return domain facts
and provenance rather than exposing internal storage handles.

## 5.6 Incremental Graph Maintenance --- P0

A source change must invalidate the smallest safely computable graph
region. The engine distinguishes node-local changes, relationship
changes, public-signature changes, file moves, deletions, and
module/target configuration changes. Invalidation decisions must be
observable in diagnostics and covered by tests. A failed incremental
update falls back to a safe broader rebuild rather than retaining stale
facts. Cache reuse is an optimization and can never override
correctness.

## 5.7 ChangeHistoryProvider --- P0

Historical evidence is accessed through an abstraction rather than
direct Git calls from rules. The provider exposes change events for
repository entities and records history boundaries, filters, and
completeness. It normalizes renames and moves where feasible and
distinguishes noise filtering from source truth. Git is the initial
implementation, but rule semantics depend on change evidence rather than
Git-specific objects. History remains lazy and is not initialized for
rule sets that do not request it.

## 5.8 Temporal Coupling --- P0

R3 computes co-change evidence between files and, where reliable,
semantic units. Temporal coupling includes observation window, co-change
count, normalized strength, and supporting commits rather than a naked
score. Generated/vendor files and bulk mechanical commits require
configurable filtering because they can dominate co-change data. A
threshold crossing produces evidence or candidates, not automatically a
technical-debt finding. Historical rules validate temporal evidence
according to their own semantics.

## 5.9 Dependency Cycles --- P0

The graph supports deterministic strongly connected component analysis
over selected dependency edge classes. Cycle evidence includes the nodes
and edges forming a representative cycle and enough provenance to
explain each edge. Users can scope cycles to target/module/type levels
to avoid mixing incomparable abstractions. The engine should not report
every combinatorial cycle path inside one SCC as separate debt. Report
semantics should represent the structural problem compactly.

## 5.10 Hotspot Evidence --- P1

R3 introduces hotspot evidence combining independent dimensions such as
change frequency, structural complexity, coupling, and debt density. The
system exposes those components individually rather than hiding them
behind an unexplained risk number. Ranking can be supported for
navigation, but the underlying factors must always be inspectable.
Hotspots are evidence about maintenance pressure, not proof that code is
badly designed. Time windows and normalization strategies are versioned
and reported.

## 5.11 Structural Communities --- P1

R3 may compute graph communities or clusters to identify strongly
connected structural neighborhoods. Community output is evidence, not an
architectural verdict. The system should compare observed communities
with package/target/module boundaries and surface meaningful
disagreements as candidates for later architectural rules. Algorithms
and parameters must be versioned because community assignments can vary.
If results are unstable or hard to explain, this capability remains
experimental.

## 5.12 Semantic/Structural Disagreement --- P1

R3 integrates R2's semantic vector index with structural topology to
identify cases where semantic neighbors and structural neighbors
disagree. For example, fraud-related behavior spread across unrelated
modules may be semantically close while structurally fragmented.
Conversely, a structurally dense module may contain unrelated
responsibilities. These mismatches are candidate evidence for
architectural drift or responsibility problems. Similarity never becomes
a finding without a rule-specific predicate.

## 5.13 Architectural Metrics --- P1

The engine may expose fan-in, fan-out, afferent/efferent coupling,
dependency depth, cycle membership, and selected centrality measures.
Metrics must have precise definitions and scopes so values are
comparable. R3 should avoid importing metric names whose semantics do
not map cleanly to Swift packages/modules/types. Centrality measures are
primarily navigation/evidence features until validated against useful
debt cases. No single metric is allowed to become a universal quality
score.

## 5.14 Explainability --- P0

Every repository-level finding must be explainable through a bounded
chain of evidence. A cycle report shows the dependency edges; temporal
coupling shows the supporting history window/commits; Feature Envy shows
ownership/reference counts; a hotspot shows each contributing factor.
The reporter must distinguish observed facts, derived evidence, and rule
conclusions. Explain output should remain useful without exposing
internal database identifiers. Machine-readable output retains enough
provenance for tooling.

## 5.15 Snapshot Completeness --- P0

R3 extends `AnalysisSnapshot` provenance to repository capabilities. A
snapshot records which indexes were complete, which history boundary was
analyzed, which capabilities failed, and which scopes were excluded.
Failure to build the call graph, semantic index, or history evidence
cannot be treated as absence. Rules requiring incomplete capabilities
must not silently emit definitive negative conclusions. This preserves
the R1 principle that failure to observe is not verified absence.

# 6. Include Design

R3 remains primarily a CLI/library product, so its design centers on
progressive disclosure, execution visibility, and evidence explanation
rather than a graphical graph explorer. The default command stays
simple: `swift-debt analyze .`; repository intelligence should appear
only as useful findings and concise stage diagnostics. Users should not
need to understand graph theory, ANN, or index persistence to interpret
normal output. Advanced commands can expose execution plans, repository
facts, cycles, hotspots, and evidence paths for investigation.
Machine-readable JSON must expose the same conceptual model without
coupling consumers to storage implementation.

A representative default interaction is:

``` text
$ swift-debt analyze .

Scope             426 Swift files
Syntax            reused 401 / rebuilt 25
Symbols           reused
References        updated 73 edges
Call graph        updated 31 edges
History           skipped
Semantic index    skipped

Findings          14
Analysis           complete
Elapsed            1.42s
```

An explain interaction should be evidence-first:

``` text
$ swift-debt explain F-204

Dependency Cycle
Payments → Authentication → Identity → Payments

Observed edges:
Payments.PaymentFlow
  calls Authentication.SessionValidator

Authentication.SessionValidator
  constructs Identity.IdentityChallenge

Identity.IdentityChallenge
  references Payments.PaymentContext

Evidence:
repositoryGraph / dependency edges
Completeness:
complete for configured scope
```

The planner should also have an advanced diagnostic representation. A
user debugging performance can request why a subsystem was activated and
which rules required it. A rule author can inspect graph queries without
receiving raw storage internals. Reports must distinguish facts, derived
evidence, and rule conclusions visually and structurally. No UI should
present a generic "architecture health: 73/100" score in R3.

``` mermaid
sequenceDiagram
    participant CLI
    participant Planner
    participant Cache
    participant Graph
    participant Rules
    CLI->>Planner: analyze(enabled rules, scope)
    Planner->>Cache: load compatible indexes
    Planner->>Graph: update invalidated regions
    Graph-->>Planner: capabilities + completeness
    Planner->>Rules: execute with shared evidence
    Rules-->>CLI: detections + evidence
```

# 7. Provide Metrics

R3 tracks both product quality and systems performance. Product metrics
include the number of rules reusing shared capabilities, explanation
completeness, graph-derived false positives, history-derived false
positives, and the percentage of findings whose evidence can be traced
to concrete source/history facts. It should also track capability
completeness failures so an apparently successful run cannot hide
degraded repository intelligence. Rule coverage is not counted merely
because a graph algorithm exists; representative positive and
adversarial negative fixtures are required. Metrics are primarily
release/engineering KPIs and do not require mandatory user telemetry.

Performance KPIs include cold graph construction time, warm cache-open
time, incremental update time, peak RSS, graph/index disk footprint,
query latency, number of invalidated nodes/edges per edit, history scan
time, and semantic-index reuse. Benchmarks must cover small, medium, and
large Swift repositories plus synthetic stress graphs. The most
important performance metric is not only cold-run speed but
**incremental amplification**: how much work a one-unit edit causes
elsewhere. The planner should record avoided work as well as performed
work so lazy capability design can be validated. Benchmarks must compare
"N rules sharing one capability" against equivalent rule-local
computation to prove R3's architectural value.

Release gates should require syntax-only rule sets to avoid
history/semantic startup, unchanged repositories to reuse compatible
indexes, and local edits to avoid full rebuilds unless correctness
requires them. Graph query p95 latency should remain bounded for the
supported repository-size envelope. A history-disabled run must not pay
Git traversal cost. A failed or incompatible cache must rebuild safely
rather than degrade correctness. Numeric thresholds should be frozen
after baseline experiments on representative repositories, then enforced
as regression budgets.

Value is determined by whether R3 reduces repeated computation while
enabling evidence that R2 cannot express cleanly. At least three
materially different rule families should consume shared repository
capabilities before release: structural topology, historical/temporal
evidence, and cross-unit affinity/coupling. The same repository fact
should produce consistent answers across rules and explain commands.
Incremental analysis should show a substantial warm-run advantage on
realistic edits. Maintainers should be able to diagnose both correctness
and performance from emitted provenance and benchmark traces.

# 8. Consider Impact

R3 depends on R2's SemanticUnit/evidence contracts,
SwiftSyntax/toolchain compatibility, symbol-resolution strategy, local
persistence, and the existing vector/similarity abstraction. Git becomes
a formal optional dependency for historical capabilities, but the core
analyzer must remain useful without repository history. The vector
database remains infrastructure behind semantic/structural indexes
rather than becoming a domain dependency. Persistent schemas need
migration/version handling because graph/index compatibility will
evolve. Any dependency whose failure affects completeness must be
represented in the snapshot.

R3 affects the rule authoring model significantly because rules should
stop rebuilding repository facts themselves. Existing R1/R2 rules can
remain local and cheap, while repository-aware rules declare
capabilities and query shared evidence. Reporter/JSON schemas expand to
represent repository evidence paths and completeness. Cache management
becomes more important because stale graph facts would be more damaging
than a missed optimization. CI integrations may need persistent cache
directories to obtain the intended performance benefits, but correctness
cannot depend on cache persistence.

Ongoing maintenance includes SwiftSyntax compatibility,
symbol-resolution behavior, graph schema revisions, cache migrations,
Git normalization, benchmark corpora, and graph algorithm validation.
History filtering and community algorithms require especially careful
versioning because small algorithmic changes can alter derived evidence.
Support documentation must explain how to diagnose incomplete analysis
and clear/rebuild incompatible caches. Performance regressions should be
treated as product regressions, not merely implementation details. The
system should expose enough diagnostics to avoid requiring users to
attach private repositories for basic support.

No additional organizational team is required by the PRD, but expertise
in Swift compiler tooling, graph algorithms, Git history analysis, and
performance engineering is relevant. Security/privacy review is
necessary for persistent caches because they may encode repository
structure, identifiers, and derived semantic data. Default behavior
remains local with no source transmission. Raw source should not be
duplicated into graph storage when a source location/reference is
sufficient. Future remote analysis would require a separate
product/security decision and is not implied by R3.

# 9. Outline Scope

R3 includes the typed RepositoryGraph, EvidenceGraph, shared repository
indexes, capability-driven planner, bounded graph query API, incremental
graph maintenance, ChangeHistoryProvider, temporal coupling,
dependency-cycle evidence, hotspot evidence, selected architectural
metrics, structural-community research, semantic/structural disagreement
evidence, expanded snapshot completeness, CLI explainability, JSON
support, cache versioning, and a benchmark suite. It also includes a
small representative set of graph-powered rules or research detectors
sufficient to prove the infrastructure. The release may enhance Fowler
smell implementations where repository evidence materially improves
them. All capabilities must remain local-first and compatible with
no-embedding/no-history configurations. R3's primary deliverable is the
reusable intelligence substrate, not raw rule count.

R3 explicitly excludes automatic refactoring, automatic code
modification, LLM-based repository review, natural-language repository
chat, IDE graph visualization, remote/cloud analysis, organization
dashboards, predictive maintenance claims, and universal architecture
scoring. It does not attempt to model every Swift compiler semantic
fact. It does not require a standalone graph database or server. It does
not promote every centrality/community metric into a debt rule. It does
not make Git mandatory for ordinary source analysis.

R3 also does not yet define intended architecture as policy; it observes
architecture. Comparing observed topology against an explicit desired
architecture belongs in a later architecture-conformance release. Rich
longitudinal trend analysis belongs in R4 even though R3 introduces
enough history to support temporal evidence. Automated remediation
belongs later because repository intelligence should first prove it can
describe impact accurately. Agent mutation remains prohibited because
safe action requires additional authority and verification contracts.
These exclusions keep R3 focused on trustworthy repository
understanding.

# 10. Make Room for Questions

Several open questions require research before architecture freeze. What
symbol identity can survive file moves and refactors well enough for
incremental graph updates without becoming a false canonical Finding
fingerprint? Which relationships require compiler/source-service
assistance beyond SwiftSyntax, and what are their platform/performance
costs? What persistence representation gives the best trade-off among
startup time, disk size, migration complexity, and query speed? How
should SwiftPM targets, Xcode targets, generated code, macros, and
conditional compilation be represented in the graph? Which graph
algorithms provide useful debt evidence without creating opaque
mathematical outputs?

Historical analysis also has unresolved questions. What default history
window is meaningful, and should it be commit-count-, date-, or
repository-size-based? How should merge commits, formatting-only
commits, generated changes, bulk renames, and vendor updates be filtered
without hiding real evidence? How reliable is symbol-level temporal
coupling compared with file-level coupling after refactors? Should
history evidence be normalized by developer activity or only by change
events? How should incomplete shallow clones be reported so rules do not
mistake limited history for weak coupling?

Performance research must determine the correct invalidation radius for
signature changes, protocol changes, extension changes, and module
configuration changes. It must compare in-memory graph reconstruction
with persistent specialized indexes. It must test whether SCC/community
results can be incrementally updated profitably or should be recomputed
on scoped subgraphs. It must quantify the break-even point for
persisting reverse indexes. It must establish repository-size envelopes
for the first supported release rather than claiming unlimited
scalability.

Product research must determine which graph evidence experienced Swift
developers actually find actionable. Dependency cycles are
straightforward, but centrality, community disagreement, and hotspot
ranking require validation to avoid sophisticated noise. The team should
test explanations with real repositories and ask whether users can move
from evidence to a concrete investigation. It should also evaluate
whether rule authors can express useful repository rules through the
proposed bounded APIs without escaping to storage internals. R3 should
freeze public APIs only after these experiments.

## Required Research Spikes

1.  **Graph Identity & Invalidation:** edit, rename, move, delete,
    protocol-change, and module-change scenarios with exact invalidation
    traces.
2.  **Symbol Resolution:** compare SwiftSyntax-only extraction with
    available compiler/source-service options for correctness and cost.
3.  **Persistence:** benchmark specialized adjacency/index storage
    versus a compact persistent graph representation.
4.  **Git Normalization:** evaluate temporal coupling under merges,
    renames, formatting commits, and generated changes.
5.  **Hotspots:** test whether change frequency + complexity +
    coupling + debt density produces useful navigation when factors are
    exposed separately.
6.  **Community Detection:** evaluate stability and explainability
    before deciding whether it graduates from experimental evidence.
7.  **Planner:** demonstrate that five rules sharing capabilities cost
    materially less than five independent repository traversals.
8.  **Scale:** establish cold/warm/incremental baselines across
    representative Swift repositories.

# 11. Proposed R3 Architecture

``` mermaid
flowchart TB
    subgraph Inputs
      S[Swift Source]
      G[Git History]
      V[Semantic / Structural Vectors]
    end

    S --> E[Extraction Layer]
    E --> SI[Syntax Index]
    E --> SY[Symbol Index]
    E --> RI[Reference Index]
    E --> CG[Call Graph]
    E --> DG[Dependency Graph]
    G --> HI[Change Index]
    V --> VI[Vector Index]

    SI --> RG[RepositoryGraph]
    SY --> RG
    RI --> RG
    CG --> RG
    DG --> RG

    RG --> EG[EvidenceGraph]
    HI --> EG
    VI --> EG

    Rules[Enabled DebtRules] --> QP[Capability Query Planner]
    QP --> RG
    QP --> EG
    EG --> Rules
    Rules --> D[Detections]
    D --> L[R1 Lifecycle / Reconciliation]
```

The `RepositoryGraph` is the observed topology, while the
`EvidenceGraph` contains derived claims. The query planner decides which
inputs and indexes are necessary for enabled rules. Rules remain
semantic authorities for deciding whether evidence satisfies a debt
predicate. R1 remains authoritative for lifecycle/reconciliation, so R3
does not redefine Finding identity or resolution semantics. This
separation is the architectural invariant that prevents repository
intelligence from becoming an uncontrolled source of truth.

# 12. Acceptance Criteria

R3 is release-ready when the RepositoryGraph and EvidenceGraph are
implemented as separate typed concepts and at least three rule families
consume shared evidence. The capability planner must demonstrably avoid
unused history/semantic work and deduplicate shared prerequisites.
Incremental updates must be correct across edit, rename, move, delete,
signature-change, and configuration-change fixtures, with safe
full-rebuild fallback. Repository-level findings must expose bounded
evidence chains and snapshot completeness. Persistent indexes must carry
compatibility metadata and rebuild safely when incompatible.

At least one deterministic topology feature, one historical feature, and
one cross-unit affinity feature must work end-to-end. Dependency-cycle
evidence is the recommended topology slice; temporal coupling or Shotgun
Surgery is the recommended history slice; Feature Envy or another
ownership-affinity rule is the recommended cross-unit slice. Hotspot
evidence should be included if its component metrics are independently
explainable and benchmarked. Community detection may remain experimental
without blocking release if its value/stability is not proven. Semantic
vector infrastructure must remain optional.

The benchmark suite must measure cold, warm, and incremental runs and
establish regression budgets before release freeze. Syntax-only
configurations must not initialize Git or semantic/vector capabilities.
Unchanged compatible indexes must be reused, and a typical local edit
must not trigger a full repository rebuild unless the change
semantically requires it. Analysis failures must produce explicit
incompleteness rather than silent absence. The final release
documentation must state the supported repository-size envelope and
known limitations.

# 13. Definition of Done

R3 is done when SwiftDebt can answer not only "what debt did a rule
observe?" but also "what repository relationships support that
conclusion, what analysis produced those relationships, what was not
observed, and how much work was required to obtain the answer?" Rule
authors can request capabilities instead of rebuilding infrastructure.
Users can inspect cycles, coupling, hotspots, and historical evidence
without learning storage internals. Incremental performance is a
first-class tested property rather than an afterthought. The
architecture remains compatible with R1's truth/lifecycle model and R2's
hybrid evidence model.

The release must leave SwiftDebt in a stronger position for R4 rather
than forcing a rewrite. Repository intelligence should be reusable by
future evolution analysis, architecture conformance, remediation
planning, and agent-facing APIs. Public abstractions should therefore
express domain capabilities rather than current implementation choices.
At the same time, R3 must resist speculative generality: only
abstractions exercised by accepted R3 use cases become public. The final
outcome is a fast, local, evidence-driven repository model that makes
sophisticated debt analysis cheaper to add and easier to trust.
