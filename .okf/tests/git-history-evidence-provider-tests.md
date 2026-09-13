---
type: Test Harness
title: Git history evidence provider tests
description: Swift Testing coverage validates deterministic Git history evidence, unavailable-history handling, and structured Git process arguments.
resource: Tests/SCMAKitTests/GitHistoryEvidenceProviderTests.swift
tags: [swift-testing, debt-analysis, git-history, fixtures]
timestamp: 2026-09-13T00:00:00Z
---

# Overview

`GitHistoryEvidenceProviderTests` creates temporary Git repositories with frozen commit timestamps and verifies the `GitHistoryEvidenceProvider` output from an end-user-style local repository.

The tests assert that available history emits `git-history.change-frequency`, `git-history.contributor-concentration`, `git-history.fix-orientation`, and `git-history.recency` evidence with stable raw values.

# Fixture support

`GitHistoryFixtureSupport` initializes temporary Git repositories, writes fixture source files, commits with injected author email and timestamp environment, constructs file-level `DebtEntity` values, and provides a recording runner for process-argument assertions.

Unavailable repository cases cover a non-repository directory, an initialized repository with no commits, and a shallow clone.

# Coverage

The harness verifies that repeated calls with the same repository and reference time produce equal results, unavailable history returns four unavailable evidence entries without normalized scores, diagnostics include the unavailable reason, and Git commands are passed as structured argument arrays rather than shell-composed strings.

# Citations

[1] [GitHistoryEvidenceProviderTests.swift](../../Tests/SCMAKitTests/GitHistoryEvidenceProviderTests.swift)
[2] [GitHistoryFixtureSupport.swift](../../Tests/SCMAKitTests/GitHistoryFixtureSupport.swift)
