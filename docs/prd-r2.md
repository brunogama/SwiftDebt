# SwiftDebt R2 — Hybrid Code-Smell Analysis

**Status:** Draft | **Release:** R2 | **Created:** 2026-09-24 | **Predecessor:** R1

## 0. Purpose
R2 extends R1's trustworthy observation pipeline into repository-aware design-smell analysis. SwiftSyntax and deterministic evidence remain primary. Local semantic embeddings/vector search are optional candidate/evidence mechanisms, never proof. The initial taxonomy targets Fowler's *Refactoring, Second Edition* smells while SwiftDebt defines explicit executable observation contracts.

# 1. Define the Basics
**Elevator pitch:** SwiftDebt R2 is a fast, local-first Swift analysis engine detecting design-level smells using the cheapest reliable evidence: syntax, metrics, symbol relationships, graphs, repository history and, only where useful, native local semantic embeddings/vector search.

Primary UX: `swift-debt analyze .`

Capabilities: Semantic Units; metric/symbol/reference/relationship indexes; hybrid structural/lexical/relational/semantic similarity; deterministic Semantic Projection; incremental persistence; formal Fowler coverage framework. R2 is not an LLM feature.

Conceptual owners: Product/Rule Semantics, Swift Static Analysis, Search/Vector Infrastructure, Developer Experience. Stakeholders: Swift developers, staff/principal engineers, architecture/platform teams, repository maintainers and coding agents.

No fixed release date. Ship when correctness, reproducibility, explainability, performance and acceptance gates pass. Current status: discovery/architecture definition.

# 2. Capture Strategy
Objective: expand SwiftDebt from local syntax detection into repository-aware design-smell detection while retaining speed, offline execution, reproducibility, inspectable evidence and CI suitability.

> Use the cheapest reliable evidence first.

`Source → SwiftSyntax → cheap predicates → metrics/structure → symbols/relationships → graph/history if required → semantic candidates if required → vector retrieval if required → rule validation → Detection`

SwiftDebt occupies the layer between syntax linting and probabilistic AI review: evidence-driven design analysis. Expected value: earlier architectural feedback, repeatable refactoring signals, repository-wide debt inventory, CI regression detection and explainable evidence.

Every finding must explain what was observed, decisive evidence, deterministic vs heuristic evidence, unavailable capabilities and material result changes.

# 3. Offer Context
Local/cheap smells include Long Function, Long Parameter List, Large Class and Message Chains. Relational smells include Feature Envy, Middle Man, Inappropriate Intimacy and Data Clumps. Historical evidence helps Shotgun Surgery/Divergent Change. Semantic similarity may help Alternative Classes with Different Interfaces and semantic responsibility duplication.

Evidence domains: syntax, metrics, symbols, references, ownership, calls, type/dependency relationships, history, lexical/structural/relationship/semantic similarity.

Use cases: `analyze .`, `analyze --changed`, `explain <finding-id>`, JSON reports and policy-driven CI.

Roadmap context: R1 trustworthy observations → R2 hybrid smells → future repository/history intelligence, architectural drift, remediation and agent APIs. Only R2 is committed here.

# 4. List Assumptions
- SwiftSyntax handles core structural extraction.
- Expensive semantic services are capability-isolated.
- Most units are rejected before embedding.
- Similarity is candidate evidence, not proof.
- Apple NaturalLanguage/NLEmbedding is the initial zero-download semantic provider.
- Structural/relationship vectors may outperform generic text embeddings for code-specific questions.
- Git evidence is optional and rule-scoped.
- Raw Swift is not canonical embedding input; a versioned deterministic Semantic Projection is.
- Default R2 needs no API key, network, Python, Ollama, inference server or LLM.

Performance hypothesis: 100% units syntax; 10–25% deeper structural candidates; 1–5% semantic candidates; <1–2% expensive cross-unit validation. Benchmark before treating these as budgets.

Reproducibility identity includes source revision, scope, rule revisions, config, projector revision, embedding identity where applicable and history boundary where applicable.
# 5. Detail Requirements
## 5.1 Semantic Units
`SemanticUnit` contains identity, kind, location, SyntaxFacts, StructuralFacts, RelationshipFacts and MetricFacts. Minimum kinds: file, type, extension, function, method, initializer, property, closure. It is analysis representation, not Finding identity.

## 5.2 Metrics
Support lines, statements, parameters, branches, loops, max nesting, calls, reads/writes, local/foreign references, closures, awaits, throws, generic parameters, fan-in/fan-out where available.

## 5.3 Relationships
Minimum vocabulary: owns, calls, calledBy, reads, writes, references, inherits, conformsTo, constructs, accepts, returns, extends, dependsOn. Efficient reverse lookup required.

## 5.4 Semantic Projection
`SemanticProjector` is Sendable, versioned and maps SemanticUnit → SemanticDocument. Projection must be deterministic, compact, formatting-independent, preserve useful identifiers/types/behavior and have golden fixtures.

## 5.5 Embedding Provider
`SemanticEmbeddingProvider` exposes identity and vector(for: SemanticDocument). Initial implementation: `AppleNLEmbeddingProvider`. Rules never depend directly on NLEmbedding. Future CoreML/code-specific/external providers remain replaceable.

## 5.6 No-Embedding Mode
`swift-debt analyze . --semantic-analysis disabled`. Rules needing unavailable evidence become unexecuted/incomplete or use an explicitly documented deterministic fallback. Missing evidence is never negative evidence.

## 5.7 Similarity Abstraction
Rules query `SimilarityIndex.nearest(...)`; they never access the vector DB directly.

## 5.8 Hybrid Similarity
Candidate scoring may combine structural, lexical, relationship and semantic similarity. Weights are versioned rule semantics/configuration, never hidden mutable constants. Deterministic normalized structural vectors require no ML and are preferred when sufficient.

## 5.9 Vector Store
Required: insert, replace, delete, metadata-filtered ANN, persistence, incremental update, provider/model namespaces and dimension validation. It is infrastructure behind SimilarityIndex.

## 5.10 Incremental Analysis
Reuse compatible unchanged facts. Rebuild changed units/affected relationships. Reuse vector if projection hash/provider identity is compatible; otherwise embed and update. Cache identity includes semantic content, analysis compatibility, projection revision and embedding identity.

## 5.11 Evidence Model
Kinds: syntax, metric, symbol, relationship, structuralSimilarity, lexicalSimilarity, semanticSimilarity, history. Evidence labels deterministic/heuristic/semantic/historical are provenance labels, not probabilities. No fake confidence percentages.

## 5.12 Rule Requirements / Lazy Capabilities
Rules declare syntax, metrics, symbols, relationships, similarity and/or history. Syntax-only workloads must not initialize embeddings, ANN or Git analysis.

## 5.13 Fowler Coverage Contract
Every targeted smell records support state, primary strategy, required/optional evidence, minimum predicate, cross-file/history/semantic requirements, false-positive/negative risks, explanation contract and benchmark fixtures.

States: **Supported**, **Partially Supported**, **Research**, **Not Reliably Observable**. A rule named after a smell is not coverage by itself.

Strategy families: metric/structural (Long Function, Long Parameter List, Global Data, Mutable Data, Large Class, Message Chains); relationship/graph (Feature Envy, Middle Man, Inappropriate Intimacy, Data Clumps, Temporary Field and observable portions of Speculative Generality/Refused Bequest); semantic/hybrid (Alternative Classes with Different Interfaces, semantic responsibility duplication); historical (Divergent Change, Shotgun Surgery). Intent-heavy smells remain partial/research when evidence cannot establish them reliably.

## 5.14 Candidate Is Not Detection
`ANN/structural match → candidate → rule-specific validation → sufficient evidence? → Detection or discard`.

## 5.15 Explainability
Example Feature Envy report: OrderPresenter.calculateTotal has 14 Order accesses vs 2 local accesses, dominant foreign ratio 87.5%, evidence relationship+metric. Never reduce explanation to an opaque similarity score.

## 5.16 Failure / Privacy
Optional semantic failure is not verified absence and is reflected in snapshot completeness. Default R2 embeds/stores locally, transmits no source, requires no telemetry and minimizes persisted raw source.
# 6. Include Design
R2 is primarily CLI/library; its design is interaction/report language. Default output shows active stages only: files parsed, symbol/relationship counts, semantic candidate count, history state and findings. Human output prioritizes rule, location/entity, explanation, decisive evidence and evidence type. Explain mode exposes deeper facts/scores. JSON exposes stable rule identity/revision, location, evidence and snapshot provenance/completeness.

Config supports rule enablement, semantic/history on/off/auto, versioned thresholds, cache directory, performance budgets and output format. Defaults require no config.

UX principles: progressive disclosure; no AI theater; no unexplained confidence; no unnecessary semantic startup; visible incompleteness; explainability is product behavior.

# 7. Provide Metrics
Product KPIs: coverage state per smell; precision on curated fixtures; known false-positive/negative cases; explanation completeness; cache hit rate; incomplete-analysis rate.

Performance KPIs: cold/warm wall time, peak RSS, parse/fact/index/embedding times, ANN latency, candidate counts, cache hit rate and single-file incremental cost. Benchmark small/medium/large real repos and synthetic 1K/10K/100K-unit workloads where relevant.

Release gates: syntax-only workloads pay zero semantic startup; unchanged units are not re-embedded; ANN candidate retrieval is bounded; semantic analysis does not dominate normal runs unless required; `--changed` scales primarily with affected units plus necessary invalidation. A smell cannot be Supported without positive fixtures, adversarial negatives, realistic examples, explanation contract and measured performance.

# 8. Consider Impact
Dependencies: SwiftSyntax/toolchain, NaturalLanguage for initial provider, project's vector DB, Git for historical rules, local cache.

R2 preserves R1 authority: Rules observe; Engine decides lifecycle/history; Reporters explain; Policy reacts; Persistence records; location is evidence not canonical identity; incomplete observation cannot establish absence.

Maintenance: toolchain compatibility, projection revisions, embedding identity compatibility, cache migrations, benchmarks, fixtures, false-positive triage and semantic rule revisions.

Security/privacy: no source leaves machine by default; document cache contents; minimize persistent semantic text. CI supports deterministic no-semantic and cached-semantic modes; missing optional capabilities cannot masquerade as complete analysis.

# 9. Outline Scope
**In:** SemanticUnit; metrics/relationships; hybrid similarity; structural vectors; Semantic Projection; Apple local embedding provider; vector index; incremental cache/invalidation; Fowler coverage matrix; explainable evidence; CLI/JSON; benchmarks; history capability boundary; representative rules across strategy classes.

**Out:** cloud LLM analysis; mandatory external models; automatic refactoring/code modification; probabilistic quality scores; repository chat; IDE GUI; universal proof of every smell; cosine similarity as debt; whole-project embedding by default; opaque learned classifiers; third-party source transmission; remediation generation.

A truthful `Not Reliably Observable` is preferable to a noisy rule.

# 10. Make Room for Questions
Open research: NLEmbedding value versus lexical/structural baselines; best semantic-unit granularity; identifier normalization; embedding stability across OS versions; provider identity requirements; which smells materially benefit from semantics; sufficient graph representation; extension/protocol ownership; generated source; minimum Git window; rename/move handling; repository vs workspace index scope; vector dimensions/quantization; invalidation radius; ambiguous candidates.

Required experiments before freeze:
1. **Embedding Value:** lexical vs structural vs relationship vs NLEmbedding(raw) vs NLEmbedding(projection) vs hybrid.
2. **Projection:** compare schemas for quality, stability, size and runtime.
3. **ANN:** measure recall and candidate explosion.
4. **Incremental invalidation:** verify exactly what recomputes after method/type/file changes.
5. **History:** validate Shotgun Surgery/Divergent Change against curated Git histories including renames/noisy commits.

# 11. Architecture
`Swift Source → SwiftSyntax → SemanticUnit Builder → {Metrics, Evidence Graph, Semantic Projection} → {Structural Index, NLEmbedding/Vector Index} → Similarity Engine → Candidate Set → DebtRule → Detection → R1 Reconciliation/Lifecycle`.

# 12. Performance Architecture
Incremental from day one: discover scope; reuse compatible facts; parse changed source; update affected relationships; execute cheap filters; project only surviving candidates; reuse embeddings by projection hash; embed misses only; bounded ANN; validate candidates; persist changed derived state. Benchmark mode exposes stage timings.

# 13. Fowler Coverage Workstream
Create a machine-readable manifest for the complete second-edition smell taxonomy. Each entry records rule identity (if any), observability state, evidence requirements, implementation status, fixture coverage and performance class. Documentation/coverage claims must be generated from or validated against this manifest.

# 14. Testing Strategy
Unit tests for metrics/relationships; golden projection tests; property-based normalization/invalidation tests; provider contract tests; smell fixtures; adversarial negatives; cross-file integration; Git-history fixtures; cache compatibility tests; performance benchmarks; end-to-end CLI tests. Do not assume exact Apple vector equality across OS versions unless guaranteed.

# 15. Acceptance Criteria
R2 is ready when:
1. SemanticUnit/evidence architecture preserves R1 authority boundaries.
2. Rules declare capabilities and expensive subsystems are lazy.
3. Structural, relational, semantic and historical paths each have representative end-to-end validation or documented research outcome.
4. AppleNLEmbeddingProvider is isolated behind an abstraction.
5. Semantic Projection is versioned and golden-tested.
6. Vector retrieval only generates candidates; rule-specific evidence validates detections.
7. Incremental cache prevents unnecessary recomputation/re-embedding.
8. Analysis snapshots record relevant capability completeness and provider/projection provenance.
9. The Fowler coverage manifest covers the complete target taxonomy without pretending undecidable smells are supported.
10. Every Supported smell has positive/adversarial/realistic fixtures and explanation tests.
11. Cold/warm/incremental benchmarks exist with regression gates.
12. Default operation is offline and requires no LLM.
13. JSON output exposes evidence and provenance sufficiently for CI/agents.
14. No optional capability failure is interpreted as verified absence.

# 16. Non-Negotiable Invariants
- Truth over continuity.
- Missing observation is not absence.
- Similarity is evidence, not truth.
- Embeddings never own Finding identity.
- Vector-store details never leak into DebtRule semantics.
- Rules observe; Engine decides lifecycle.
- Expensive work is demand-driven.
- Unchanged compatible work is reused.
- Explainability is required for a detection.
- Performance is a release feature, not post-release optimization.
