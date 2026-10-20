# Swift testing pipeline

The `swift-debt pipeline` commands implement a conservative SwiftDebt policy informed by
`technical-debt-frameworks-research.md`, sections 6 and 9.5. A deterministic
planner chooses checks. A serial runner executes explicitly configured commands
and retains their results.

The pipeline accepts declared change risk and impact certainty. It does not
infer either from a debt score, prove finding resolution, or implement the
runtime detector providers deferred by ADR 0001.

---

## Commands

```sh
swift build --build-tests
.build/debug/swift-debt pipeline plan .swift-debt-pipeline.example.json
.build/debug/swift-debt pipeline run .swift-debt-pipeline.example.json \
  --artifacts /tmp/swift-debt-pipeline-run-001
```

`plan` validates configuration and prints the plan as JSON without executing
commands or creating artifacts. `run` prints a JSON report. Child output goes to
log files, so it does not corrupt the report on standard output.

The configuration path and artifact path resolve relative to the invoking
directory. Commands run in the configuration file's parent directory. The
artifact directory must not already exist.

The repository example runs compiler and catalog validation, domain boundary
tests, unit and integration tests, the full Swift Testing suite with the repository's
100% Core line-coverage gate, and real
CLI/plugin smoke tests. Its `impact` is `uncertain`, so the full suite is required.
The example intentionally overlaps focused suites and full regression for clear
per-check evidence. It is a starting configuration, not a claim of minimum runtime.
The coverage script runs instrumented tests serially to keep coverage counters
consistent. Ordinary test runs can remain parallel.

---

## Selection policy

| Context | Required checks | Advisory checks |
| --- | --- | --- |
| Every run | `staticAnalysis`, `architecture`, `unit`, `integration`, `endToEnd` | None |
| Pull request with known impact | `regression` | None |
| Uncertain impact or scheduled run | `fullRegression`, replacing `regression` | None |
| High or critical risk | `property` | `mutation`, `dynamicAnalysis` |
| Scheduled run | `property`, `dynamicAnalysis`, `dependencies` | `mutation` |

Policy revision `1` requires end-to-end checks on every run, a stricter baseline
than the research's generic risk-based recommendation. `policyRevision` identifies
the selection policy independently of the JSON schema version.

Overlapping requirements occur once. A required check takes precedence over an
advisory selection. Checks run in a fixed order, serially, even after a failure,
so the report retains the other available evidence.

Change risk accepts `low`, `medium`, `high`, or `critical`. Trigger accepts
`pullRequest` or `scheduled`. Impact accepts `known` or `uncertain`. These are
explicit policy inputs rather than calibrated predictions.

The repository still requires the full test suite before completion. A known
impact configuration can bind `regression` to `swift test`; the planner does not
authorize skipping project-required validation.

---

## Configuration and artifacts

Configuration has `schemaVersion: 1`, a `context`, and a `commands` array. Each
command has `check`, `executable`, `arguments`, and `timeoutSeconds`. All fields
are required in JSON. Executable paths must be absolute. Timeouts must be finite,
greater than zero, and at most 86400 seconds.

Duplicate bindings and invalid configuration are rejected before execution.
Missing bindings produce `unavailable` results. Bindings for checks outside the
plan are not executed.

Commands execute directly as an executable and argument array. Shell expansion
does not occur unless the configuration explicitly invokes a shell. Configuration
is trusted executable input, like a CI workflow. Arguments are retained in
`configuration.json`; credentials should be supplied through the environment.

```text
artifact-directory/
  configuration.json
  plan.json
  staticAnalysis.result.json
  report.json
  staticAnalysis.stdout.log
  staticAnalysis.stderr.log
  ...results for every planned check and logs for executed checks
```

The runner writes the configuration and plan before execution, writes each result
atomically after its check, and writes `report.json` last. An interrupted run may
retain partial evidence without a final report. Such a directory is incomplete
and cannot be resumed or reused.

The runner captures output directly to files and bounds command runtime. Timeout
handling terminates the direct process and escalates to forced termination if
needed. It does not provide process-group isolation for descendants. Use commands
that own and clean up their children.

---

## Verdicts and evidence limits

| Exit | Verdict | Meaning |
| --- | --- | --- |
| 0 | `passed` | Every required check passed |
| 1 | `failed` | At least one required check failed or timed out |
| 2 | `inconclusive` or command error | Required evidence is unavailable, or configuration/execution setup is invalid |

A required failure takes precedence over unavailable evidence. Advisory failures
remain in the report and do not change the verdict. Missing or duplicate results
cannot satisfy a requirement.

Decoded plans must match the current policy exactly. Decoded reports recompute
the verdict from the plan and results and reject contradictions. These checks
validate consistency; they do not authenticate the commands or their assertions.

A passing command proves only its configured assertion. The runner does not
verify that a test filter selected tests, measure coverage, validate a mutation
tool, or infer that removed findings were resolved. Bind checks to commands that
fail when their required evidence is absent.

`SwiftDebtCore` owns the planner and evaluator. `SwiftDebtKit` owns configuration,
process execution, and artifact persistence. The CLI owns argument parsing and
exit status. No new package dependency is required.
