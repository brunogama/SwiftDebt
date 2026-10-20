# Research pipeline design

Status: implementation design for `feat/debtmap`. The local testing pipeline is
the first implementation slice. Finding reconciliation, persistent analysis
history, and outcome measurement below are proposed work, not shipped behavior.

This design applies the research in
[`technical-debt-frameworks-research.md`](../technical-debt-frameworks-research.md),
especially sections 5, 6, 9, 10, and 18. It preserves
[ADR 0001](adr/0001-r2-open-questions.md) and the
[R2 vocabulary](SwiftDebt_R2_Rule_Catalog_Evidence_PRD/prd.md).

---

## Problem

SwiftDebt already provides source analysis, rule metadata, capability and evidence
contracts, ranked debt reports, Git-history evidence, and report comparison.
These mechanisms answer different questions. Detection establishes a claim about
code. Ranking estimates the importance of addressing it. Tests establish the
properties they cover. Report removal alone establishes none of these.

The pipeline must connect these results without turning missing evidence into
success or treating a lower score as proof of safer software. It must also remain
a Swift library and CLI, with deterministic domain logic and auditable artifacts.

---

## Usage from the caller's view

The immediate CLI surface is:

```sh
swift-debt pipeline plan .swift-debt-pipeline.example.json
swift-debt pipeline run .swift-debt-pipeline.example.json \
  --artifacts /tmp/swift-debt-run-001
```

Planning executes no commands. Running writes configuration, a versioned plan, per-check results and logs, and
a final report in a new directory. The
[testing pipeline reference](TESTING_PIPELINE.md) defines its schema and exits.

The same policy is available without process execution:

```swift
import SwiftDebtCore

let context = PipelineContext(
    risk: .high, trigger: .pullRequest, impact: .uncertain)
let plan = PipelinePlanner.plan(context: context)
let evaluation = PipelineEvaluator.evaluate(plan: plan, results: checkResults)
```

A local tool can execute configured checks through one service call:

```swift
import Foundation
import SwiftDebtKit

let report = try PipelineService().run(
    configuration: configuration,
    workingDirectory: repositoryURL,
    artifactsDirectory: newRunDirectory)
```

`checkResults`, `configuration`, and the URLs are caller-supplied values. An
evaluation is a testing verdict, not a Finding transition. The current report is
a local execution receipt; it is not sufficient for importing cross-run
resolution evidence.

---

## End-to-end flow and ownership

```text
Source + configuration + catalog + capabilities
                       |
                       v
                AnalysisService
                       |
          Detections + Observation States
                       |
                       v
           Versioned analysis snapshot
                       |
            +----------+----------+
            |                     |
            v                     v
     Finding reconciliation   Metrics + Git history
            |                     |
            |                     v
            |              Risk assessment
            |                     |
            +----------+----------+
                       |
                       v
                   Test plan
                       |
            Configured check execution
                       |
                       v
                Validation evidence
                       |
                       v
           Remediation record + later outcomes
```

The diagram includes proposed stages. It does not imply that the current
`pipeline run` command performs source analysis or reconciliation.

| Knowledge | Owner | Current status |
| --- | --- | --- |
| Rule identity, revisions, evidence predicates, observability | `SwiftDebtCore/RuleCatalog` | Existing |
| Syntax observations and source analysis | `SwiftDebtSyntax`, composed by `SwiftDebtKit.AnalysisService` | Existing capabilities; some claims remain partial |
| Metrics, score contributions, unavailable scoring evidence | `SwiftDebtCore` | Existing |
| Git subprocesses and history extraction | `SwiftDebtKit` | Existing |
| Report formats and rendering | `SwiftDebtReporting` | Existing |
| Cross-run Finding lineage and resolution | Pure Core transition logic, Kit snapshot storage | Proposed |
| Change-risk test selection and result evaluation | `SwiftDebtCore.PipelinePlanner`, `PipelineEvaluator` | Immediate slice |
| Local command execution and artifacts | `SwiftDebtKit.PipelineService` | Immediate slice |
| CLI parsing and process exit status | `swift-debt` | Immediate slice |
| Remediation history and outcome aggregation | Core values, Kit persistence | Proposed |

Core imports no external modules. Kit owns filesystem and process operations.
The CLI adapts user input to these APIs. Existing analysis services remain the
composition boundary; the pipeline does not introduce another analyzer.

---

## Proposed snapshot and lifecycle contract

The future snapshot envelope records source revision and dirty-content identity,
analyzed scope, source classifications, toolchain, catalog and capability
versions, rule revisions, and observation completeness. A Git commit alone is
insufficient for a dirty worktree.

The following is a proposed type sketch, not a declaration of existing APIs:

```swift
struct AnalysisSnapshot: Sendable {
    let identity: SnapshotIdentity
    let observations: [RuleObservation]
    let metrics: [VersionedMetric]
}

struct RuleObservation: Sendable {
    let subject: SubjectIdentity
    let rule: RuleIdentity
    let semanticRevision: SemanticRevision
    let evidenceRevision: EvidenceRevision
    let state: ObservationState
    let detections: [DetectionSnapshot]
}

enum FindingDisposition: Sendable {
    case observed
    case persisting
    case changed
    case ambiguous
    case unobservable
    case resolved(AbsenceEvidence)
}
```

`SnapshotIdentity`, `SubjectIdentity`, `VersionedMetric`, `DetectionSnapshot`, and
`AbsenceEvidence` require concrete contracts before implementation. In
particular, only the reconciler may construct `AbsenceEvidence` after verifying
scope, identity, semantic compatibility, and complete observation.

Locations are evidence, not persistent identity. Rename and movement matching
must preserve lineage only when the match is unambiguous. An uncertain match
produces `ambiguous`. Semantic changes require explicit compatibility handling;
an Evidence Revision change alone preserves the semantic claim under ADR 0001.

```text
Previous Finding + current comparable observation
    |
    +-- matching Detection -----------------> persisting / changed
    +-- ambiguous subject match ------------> ambiguous
    +-- partial / unavailable / failed
    |   / disabled / unevaluated scope ------> unobservable
    +-- complete observation + no Detection
        + proven comparable subject/scope --> resolved
```

`ObservationState.complete` with zero Detections is necessary for absence, but
cross-run resolution also needs comparable scope and subject identity.
`DebtReportComparator` currently reports removed IDs; it must not be relabeled
as a reconciler.

---

## Risk, policy, and evidence

Detection is independent of ranking. Low change frequency cannot erase a
concurrency violation. Policy handles source classification and mandatory
obligations without changing a Rule Definition's Semantic Revision.

Risk assessment preserves raw inputs, measurement windows, calculation versions,
normalization, confidence, and contribution breakdowns. Git commit-subject
classification remains a defect proxy. Missing data remains unavailable. The
research's numerical weights are hypotheses for calibration, not production
defaults or financial estimates.

The immediate pipeline accepts declared `PipelineRisk`, `PipelineTrigger`, and
`PipelineImpact`. These types do not alias debt `Priority`. No automatic mapping
from the worst debt score to change risk is introduced.

| Situation | Testing policy |
| --- | --- |
| Every run | Static, architecture, unit, integration, and end-to-end checks |
| Known pull-request impact | Regression check |
| Uncertain impact or scheduled run | Full regression replaces targeted regression |
| High or critical risk | Required property checks; advisory mutation and dynamic analysis |
| Scheduled run | Required property, dynamic-analysis, and dependency checks; advisory mutation |

Project-required gates remain mandatory. This repository's example uses the
full suite and compiler/catalog validation. A command binding is trusted input;
the runner cannot infer whether the command actually tests its claimed category.

The initial policy is deliberately conservative for this analyzer's CLI and
plugin workflows: end-to-end checks remain required even at low risk. This is
stronger than the research's generic high-risk E2E recommendation. Focused suites
also remain separately evidenced when full regression is selected. The policy
does not claim minimum test cost; changing it requires explicit policy revision
and measured evidence.

---

## Execution, persistence, and retries

The immediate implementation uses a deterministic plan and a serial process
runner. Configuration is validated before side effects. Commands receive an
executable and argument array without implicit shell expansion. Child input is
closed, and output streams directly to per-check files.

Missing bindings or launch failures yield unavailable evidence. A required
nonzero exit or timeout fails the run. Missing required evidence is inconclusive.
Advisory failures remain visible. Duplicate results cannot satisfy a requirement.

Each invocation owns a new artifact directory. Configuration is written before
execution and `report.json` is published atomically after evaluation. A crash
can leave logs without a final report; that directory is incomplete and must
never be interpreted as passing. Retrying uses a new directory and reruns the
checks. This is not an exactly-once execution guarantee.

Commands must be safe to rerun. The runner supervises only the directly launched
process. Descendant cleanup and CI cancellation remain limitations; a process
group contract must be designed before offering stronger guarantees.

Future analysis snapshots should use the same immutable publication pattern.
Cross-run evidence must additionally bind source identity, scope, policy version,
plan identity, and artifact digests. The current execution receipt lacks that
binding and must not be imported as proof of Finding resolution.

---

## Remediation and outcomes

A proposed remediation record links the before and after snapshots, change
revision, Finding transitions, added tests, and validation artifacts. Immediate
technical results and delayed engineering outcomes are separate records.

Examples of immediate results are a verified absent Detection or a removed
dependency cycle with regression tests passing. Later outcomes include recurrent
defects, triage time, maintenance effort, and change lead time. Neither a lower
score nor an observational association establishes causal productivity gains.

---

## Alternatives and synthesis

| Design | Hides | Exposes | Assessment |
| --- | --- | --- | --- |
| Pure planner with externally supplied results | Selection and verdict rules | CI execution, provenance binding, finalization | Strong future distributed boundary; incomplete local user workflow alone |
| Native planner with serial runner | Selection, launch, timeout, logs, verdict | Trusted commands and direct-process limits | Implemented local slice |
| Stateful scheduler and database | Background work and indexed history | Operations, migrations, shared-state coordination | No demonstrated need for this branch |

The selected base is the bounded local-receipt design. The independent Sol
candidate also preferred a native runner, but proposed mandatory run IDs, source
revisions, workspace fingerprints, and retry relationships in the immediate API.
Those additions are deferred because this slice does not import cross-run
evidence or claim remediation proof.

The cross-judge selected the bounded design and identified three useful additions
from the Sol candidate:

1. Version selection semantics with `policyRevision`, independently of JSON schema.
2. Publish `plan.json` before execution and an atomic result for each planned check,
   then publish `report.json` last.
3. Restrict construction of derived plans and verdicts, and reject invalid decoded
   plans so an empty plan cannot be presented as passing verification.

These safeguards are implemented in the local slice. Typed process exit codes
and unavailability reasons are a later interchange improvement; current command
details and logs remain local diagnostic evidence.

The configured Fable and Opus lanes failed authentication. The completed
comparison used the parent design, the Sol candidate, and a fresh Sol cross-judge.
It therefore has independent review but no cross-provider corroboration.

---

## Open decisions and accepted limits

- Which Swift mutation operators detect meaningful regressions on this corpus?
  Keep mutation advisory until a pilot measures useful mutants and execution cost.
- Which subject anchors survive real refactors without merging distinct Findings?
  Do not implement automatic resolution until rename, split, merge, and ambiguity
  fixtures establish that contract.
- Which source and environment identities make two snapshots comparable?
  Require explicit content and revision provenance in the future snapshot
  contract; the current local command receipt makes no comparability claim.
- How should CI cancellation propagate to descendant processes?
  The initial runner supervises direct processes only. Stronger process-tree
  control needs a separate platform-specific design and tests.
- Which outcome measurements justify changes to ranking weights?
  Preserve raw evidence and version policy changes rather than rewriting history
  or treating the research's illustrative coefficients as validated defaults.

These decisions do not block the local testing slice. They are gates for the
later capabilities that depend on them.

---

## Implementation and verification sequence

| Unit | Deliverable | Acceptance gate |
| --- | --- | --- |
| 1 | Pure planner and evaluator | All risk/trigger/impact combinations; missing, duplicate, advisory and failed results; stable ordering and Codable contracts |
| 2 | Native runner and CLI | Real subprocess pass/fail/timeout/launch-error tests, preserved stdout/stderr, no plan side effects, safe artifact reuse rejection |
| 3 | Observation-aware snapshots | Positive/adversarial rule fixtures; failed or partial analysis cannot prove absence; explicit scope and revision identity |
| 4 | Finding reconciliation and baseline policy | Rename, movement, ambiguity, scope changes and disabled rules; no new prohibited debt; no resolution from missing evidence |
| 5 | Versioned risk and remediation records | Missing-data behavior, critical obligations, replay under policy changes, before/after validation |
| 6 | Historical outcomes | Immutable history, explicit measurement windows, separation of technical improvement from causal claims |

Units 1 and 2 are the current implementation slice. Units 3 through 6 require
their own contracts and tracked work. Runtime/external detector providers and
interprocedural analysis remain R3 work under the accepted ADR.

Verification for the immediate slice includes `swift build --build-tests`,
`swift test`, Core line coverage, CLI/plugin smoke tests, formatting, and scoped
lint. Existing performance budgets remain in place. No performance improvement
is claimed without a comparable benchmark.
