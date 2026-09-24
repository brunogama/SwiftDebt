---
type: Evidence Provider
title: Git history risk evidence
description: SwiftDebtKit derives deterministic debt evidence from bounded local Git history for file-level entities.
resource: Sources/SwiftDebtKit/GitHistoryEvidenceProvider.swift
tags: [swift, debt-analysis, git-history, swiftdebtkit]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`GitHistoryEvidenceProvider` accepts a repository root, injected reference time, and debt entities, then returns sorted `DebtEvidence` and warning diagnostics for local Git history.

The provider rejects unavailable history with explicit unavailable evidence instead of fabricated zero-valued risk when the root is not a Git repository, the repository is shallow, the repository has no commits, an entity has no file location, or no commits match the entity file.

# Git process execution

`GitHistorySubprocessRunner` invokes `/usr/bin/env git` with structured arguments, captures stdout and stderr in temporary files, enforces a timeout, and reports `GitHistoryProcessResult` with exit code, output, and timeout state.

The provider validates repository state with `rev-parse --is-inside-work-tree`, `rev-parse --is-shallow-repository`, and `rev-list --count HEAD` before running a rename-aware `git log --follow` query for each distinct entity file. Each query reads at most 501 commits, retains at most 500, and reports whether the history was truncated. Subprocess completion uses termination signaling rather than polling, so short Git commands do not incur a fixed sleep.

# Evidence kinds

Available matching commits produce four required evidence kinds per entity:

| Kind | Raw value basis | Score basis |
|------|-----------------|-------------|
| `git-history.change-frequency` | matched commit count | commit count scaled by 20 and capped at 100 |
| `git-history.recency` | days since latest matched commit and injected reference time | recency decay from the injected reference time |
| `git-history.fix-orientation` | fix-oriented commit count | share of subjects containing fix, bug, crash, defect, regression, hotfix, or repair tokens |
| `git-history.contributor-concentration` | unique contributor count and top share | top contributor share |

Contributor identities are counted internally but omitted from evidence output.

# Determinism

Entities, commits, paths, and evidence are sorted through deterministic ordering helpers. Recency uses the request's `referenceTime`, not an ambient clock, and ISO 8601 formatting is centralized for stable raw values.

# Citations

[1] [GitHistoryEvidenceProvider.swift](../../Sources/SwiftDebtKit/GitHistoryEvidenceProvider.swift)
[2] [GitHistoryEvidenceFactory.swift](../../Sources/SwiftDebtKit/GitHistoryEvidenceFactory.swift)
[3] [GitHistoryParsing.swift](../../Sources/SwiftDebtKit/GitHistoryParsing.swift)
[4] [GitHistoryProcess.swift](../../Sources/SwiftDebtKit/GitHistoryProcess.swift)
