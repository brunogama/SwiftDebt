# Prioritize Aged Force Tries

Use Git blame evidence to find `try!` expressions that survived a later commit.

---

## Rule contract

The optional `swiftdebt.aged-force-try` rule reports a `try!` only when `git-blame-v1` establishes that the line's last-change revision is a strict ancestor of the clean Git `HEAD` captured for the analysis. Its Semantic Revision is 1 and its default severity is warning.

The rule complements `swiftdebt.force-try`. The syntax-only rule reports every `try!`; the aged rule helps prioritize occurrences that remained after the commit that last changed their line.

Run it with an explicit Git executable:

```sh
swift-debt analyze /path/to/repository \
  --aged-force-try \
  --git-blame-provider /absolute/path/to/git \
  --lifecycle-artifact .swift-debt/lifecycle.json
```

The executable is invoked directly with an argument vector. SwiftDebt verifies that the provider sees the captured `HEAD`, that the tracked working tree remains clean, that committed source bytes equal the analyzed `SourceUnit`, that blame covers the same source lines, and that every reported line revision belongs to the captured `HEAD` ancestry.

---

## Respond to a detection

Replace `try!` with explicit error handling when the caller can recover:

```swift
do {
    let value = try loadValue()
    use(value)
} catch {
    report(error)
}
```

Propagate the error when the caller owns the recovery decision:

```swift
func refresh() throws {
    let value = try loadValue()
    use(value)
}
```

If an invariant truly makes failure impossible, encode and test that invariant close to the throwing boundary. A comment beside `try!` does not prevent the process from terminating when the invariant changes.

---

## Evidence limits

Git line age is prioritization evidence. It does not prove runtime reachability, ownership, intent, or defect severity. Moving or reformatting code can also change blame attribution.

The CLI-supplied executable is a trusted integration input. SwiftDebt validates its output against captured repository and source facts, but the lifecycle artifact does not attest the executable path or bytes. A provider with different semantics requires a new capability contract rather than reusing `git-blame-v1`.

Selecting `--aged-force-try` without `--git-blame-provider`, or receiving missing, failing, malformed, stale, or source-mismatched evidence, makes the rule explicitly unsupported and exits with status 2. In lifecycle analysis, `git-blame-v1` is recorded as unavailable, so the missing Detection cannot establish absence or resolve the prior Finding.

Capability comparison is currently snapshot-wide. Losing `git-blame-v1` can therefore conservatively block cross-snapshot claims for other rules in the same snapshot. Historical introduction inference does not reconstruct this optional provider and reports its historical comparison as unavailable.
