# Debt Evidence and Missing Data

Ranked debt items carry evidence rather than only a score. Each evidence record names a kind, an availability state, a raw observation, a weight, and, when measurable, a normalized score. The report keeps source locations and explanatory notes so that you can trace a rank back to an observation.

## Structural and source evidence

The parser extracts complexity, duplication, dependency, and Swift-specific syntax facts from selected source. These facts do not require a Git repository or coverage file. They remain syntactic estimates: SwiftDebt does not build the project, resolve overloads, evaluate conditional compilation, or expand macros.

---

## Coverage evidence

Pass an LCOV file with `--lcov PATH` or configure `lcovPath`. The matcher records how a coverage record matched a source location. A measured zero-coverage state differs from a missing file or an unmatched entity. Use `swift-debt explain coverage` to inspect matching strategies when a coverage result looks wrong.

---

## Git-history evidence

Pass `--debt-reference-time TIME` or set `debtReferenceTime` before using recency. SwiftDebt runs `git log --follow` for each file, considers at most the latest 500 file commits, and reports when that history was truncated. It also records change frequency, fix-oriented commit share, and contributor concentration. Use `--git-executable /absolute/path/to/git` when the desired Git installation is outside `PATH`.

History can be unavailable for an uncommitted file, a shallow repository, a file with no matching commits, a failed subprocess, or a missing reference time. The report keeps these reasons under `missingEvidence`; it does not invent a zero-risk observation. Check both the score breakdown and missing-evidence list before enforcing a maximum score.
