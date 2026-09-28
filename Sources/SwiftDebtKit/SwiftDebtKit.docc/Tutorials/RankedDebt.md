# Rank Debt with Git History

Create a ranked report, inspect missing evidence, and supply a fixed reference time for Git history.

## Generate a ranked report

Run this command from the SwiftDebt repository root:

```sh
swift run swift-debt debt analyze Examples/Sources \
  --format json \
  --aggregation none \
  --debt-reference-time 2026-09-12T00:00:00Z \
  --output /tmp/swift-debt-ranked.json
```

The JSON contains `items`, `compactItems`, `summary`, and `missingEvidence`. Each item has a score breakdown and source location. `--aggregation none` keeps this first report focused on individual items.

---

## Read missing evidence

When a source has no matching commit, or the analyzed directory is outside a Git worktree, Git-history evidence is unavailable. Missing evidence is recorded under `missingEvidence`; the scorer does not turn an unavailable measurement into a zero-valued risk.

Run the command against a committed project to collect history:

```sh
swift run swift-debt debt analyze /path/to/git/project \
  --format json \
  --debt-reference-time 2026-09-12T00:00:00Z
```

Use a reference time that fits your report's comparison period. Passing the same time on repeated runs removes the ambient clock from recency scores. If Git is installed outside `PATH`, add `--git-executable /absolute/path/to/git`.

---

## Narrow the report

Use `--level file`, `--category git-history`, or `--top 10` to select the ranked entries you need. These filters operate on ranked output; they do not change the source analysis. See <doc:Evidence> for the meaning of available and missing evidence.
