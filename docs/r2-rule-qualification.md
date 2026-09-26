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
source used by the CLI. Manifest validation removes each case-specific symbol
salt and rejects duplicate rendered sources across the entire synthetic
corpus. The corrected unnamed-parameter family and the three replacement
negative families are self-contained, compile-valid Swift rather than
identifier-renamed copies.

Each published case result contains:

- rule identity and semantic revision;
- provisional author label and pending review state;
- repository shape and distinct case pattern;
- a SHA-256 identity over framed relative paths and source bytes;
- every materialized source path and its exact one-based line span;
- confusion-matrix classification against the provisional label; and
- complete primary, compared-unit, and decisive-fact locations for every
  observed Detection.

The evaluator batches the 210 synthetic cases into three repository runs. Case
boundaries remain auditable because every source path maps to one immutable
case ID. Detections are indexed by both rule identity and case ID, so a
Detection from one rule cannot be attributed to the other rule's case. Any
Detection spanning two cases fails the engineering gate.

| Repository shape | CLI selection | Data Clumps | Repeated Switches |
|---|---|---:|---:|
| `flat-single-module` | Flat source-root discovery | 10 positive, 20 negative | 10 positive, 20 negative, 10 out of scope |
| `nested-source-tree` | Recursive nested-directory discovery | 10 positive, 20 negative | 10 positive, 20 negative, 10 out of scope |
| `explicit-multi-module` | Explicit manifest with three modules | 10 positive, 20 negative | 10 positive, 20 negative, 10 out of scope |

The 30 Repeated Switches cases outside the observable rule scope remain
published with their source spans and any observed detections. They are
excluded from the confusion matrix. Ten contain candidate-equivalent case
partitions in a different order, which require semantic equivalence and
reachability analysis. Ten use compound discriminator expressions that the
syntax rule explicitly excludes. Ten place identical switches in different
textual scopes, which the rule does not compare. Three new in-scope negative
families preserve 60 adversarial negatives: they change the selected case set,
associated-value constraints, or branch partition cardinality.

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
confusion matrix until the reviewers assign independent case labels. The
report also carries provisional audit notes so reviewers see known ambiguity
before assigning those labels:

- The two Swift Algorithms Data Clumps observations combine equal `Index`
  spellings from distinct nested collection types. They are likely false
  positives because textual spelling does not establish compiler type
  identity.
- The four Swift Argument Parser Data Clumps observations overlap one
  `CommandConfiguration` property and initializer family. They are not four
  independent confirmations of a smell.

---

## Provisional results

The checked-in `qualification-report.golden.json` is the canonical report for
semantic revision 2. Its synthetic results are measured against author labels:

| Rule | TP | FP | TN | FN | Precision | FPR | Recall |
|---|---:|---:|---:|---:|---:|---:|---:|
| Data Clumps | 30 | 0 | 60 | 0 | 1.000000 | 0.000000 | 1.000000 |
| Repeated Switches | 30 | 0 | 60 | 0 | 1.000000 | 0.000000 | 1.000000 |

These figures are provisional and use only the 30 positive and 60 adversarial
negative author labels per rule. The 30 Repeated Switches out-of-scope cases
are listed separately and cannot improve or worsen the matrix. The report
publishes the declared observable scope, exclusions, known false-positive
risks, known false-negative risks, false-positive case IDs, false-negative
case IDs, and out-of-scope case IDs for each rule.

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
python3 -m unittest scripts/tests/test_repository_qualification.py

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
