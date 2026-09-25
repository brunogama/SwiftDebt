# R2 repository rule qualification corpus

This corpus exercises Data Clumps and Repeated Switches through the shipped
`swift-debt` CLI. It supplies provisional engineering evidence for rules that
remain `Research`. It does not promote either rule to `Supported` because the
two required qualified Swift reviewers have not adjudicated the labels.

---

## Frozen data shape

The versioned manifest is
`Tests/SwiftDebtKitTests/Fixtures/RepositoryQualification/corpus-v1.json`.
Each family expands to ten immutable case IDs. The checked-in renderer records
a distinct ambiguity or benign pattern for every case and produces the Swift
source used by the CLI.

Each published case result contains:

- rule identity and semantic revision;
- provisional author label and pending review state;
- repository shape and distinct case pattern;
- a SHA-256 identity over framed relative paths and source bytes;
- every materialized source path and its exact one-based line span;
- confusion-matrix classification against the provisional label; and
- complete primary, compared-unit, and decisive-fact locations for every
  observed Detection.

The evaluator batches the 180 synthetic cases into three repository runs. Case
boundaries remain auditable because every source path maps to one immutable
case ID. Any Detection spanning two cases fails the engineering gate.

| Repository shape | CLI selection | Cases per rule |
|---|---|---:|
| `flat-single-module` | Flat source-root discovery | 10 positive, 20 negative |
| `nested-source-tree` | Recursive nested-directory discovery | 10 positive, 20 negative |
| `explicit-multi-module` | Explicit manifest with three modules | 10 positive, 20 negative |

---

## Real-world snapshots

Only the listed source files are redistributed. Each snapshot carries the full
upstream Apache-2.0 license with the Swift runtime exception, exact commit,
checkout command, upstream-to-local path mapping, per-file SHA-256 digest, and
aggregate source-tree digest. The evaluator rejects changed bytes before
running the CLI.

| Repository | Pinned commit | Included sources |
|---|---|---:|
| `apple/swift-argument-parser` | `cdc5f0c6e836de848699ae11f6480f2d99ac5ef1` | 4 |
| `apple/swift-algorithms` | `5b7143f8e291dee0e14c118fd0212487f0b37af5` | 4 |

Snapshot observations retain decisive locations but remain excluded from the
confusion matrix until the reviewers assign independent case labels.

---

## Provisional results

The checked-in `qualification-report.golden.json` is the canonical report for
semantic revision 2. Its synthetic results are measured against author labels:

| Rule | TP | FP | TN | FN | Precision | FPR | Recall |
|---|---:|---:|---:|---:|---:|---:|---:|
| Data Clumps | 30 | 0 | 60 | 0 | 1.000000 | 0.000000 | 1.000000 |
| Repeated Switches | 30 | 0 | 60 | 0 | 1.000000 | 0.000000 | 1.000000 |

These figures are provisional. The report publishes the declared observable
scope, exclusions, known false-positive risks, known false-negative risks,
false-positive case IDs, and false-negative case IDs for each rule.

Both pinned snapshots completed exact analysis. At the pinned source selection,
Swift Argument Parser produced four Data Clumps Detections and one Repeated
Switches Detection. Swift Algorithms produced two Data Clumps Detections and
one Repeated Switches Detection. Those observations are not labeled outcomes.

---

## Determinism and network evidence

The determinism fixture is committed to a temporary Git repository with fixed
identity and dates. Before and after every CLI run, `git status --porcelain`
must be empty. The evidence sidecar is written outside the analyzed repository.

The gate runs ten times at each parse job count `1`, `2`, and `8`. All 30 raw
sidecars must be byte-identical. A final run uses the default CLI configuration
inside a macOS sandbox profile that denies all network operations, and its raw
sidecar must equal the unsandboxed baseline.

Run the exact gate after building the executable:

```sh
python3 scripts/evaluate_repository_qualification.py \
  --swift-debt .build/debug/swift-debt \
  --output /tmp/swiftdebt-rule-qualification.json \
  --work-directory /tmp/swiftdebt-rule-qualification-review \
  --expect Tests/SwiftDebtKitTests/Fixtures/RepositoryQualification/qualification-report.golden.json \
  --determinism-runs 10 \
  --parse-jobs 1,2,8 \
  --verify-network-denied
```

The review directory must not already exist. It retains all materialized Swift
sources, CLI sidecars, and determinism outputs outside repository history.

---

## Review gate

The manifest reserves two reviewer slots. Both are `pending`, and adjudication
is `pending`. Reviewers must label cases independently, record disagreements,
and record their adjudication before the confusion matrix can qualify either
rule for `Supported` status. Until then, the published release qualification is
`blocked-pending-independent-review` even when all engineering checks pass.
