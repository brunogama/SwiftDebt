---
name: verify-swift-debt
description: "Drive the SwiftDebt CLI and SwiftPM plugin workflows end to end when verifying source analysis, ranked debt reports, package integration, or pipeline execution."
---

# Verify SwiftDebt

Use this skill when a change affects the SwiftDebt CLI, ranked debt workflows,
report rendering, SwiftPM plugin integration, or pipeline execution. The primary surface is the
short-lived `swift-debt` executable. The repository also contains an optional
interactive terminal debt explorer and two SwiftPM plugins; those are driven as
separate, isolated checks.

## Launch

From the repository root, build the executable and test products once:

```sh
swift build --build-tests
```

The launch artifact is `.build/debug/swift-debt`. Readiness is established by
the executable returning successfully from:

```sh
.build/debug/swift-debt --version
```

The version must equal `SwiftDebt $(cat VERSION)`. This CLI has no daemon or
port. Each drive starts a new process and can run independently. There is no
server teardown; remove only the fixture directory created by the drive.

## Doctor

Run the read-only doctor before driving a feature:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh --doctor
```

The doctor checks that the already-built binary exists, reports the repository
version, and exposes the expected `analyze`, `debt`, and `pipeline` commands in help output.
It does not analyze files, write reports, or change the checkout. If it fails,
run the Launch command and then retry the doctor.

## Drive

The maintained helper runs a real user path and writes proof artifacts without
touching repository source files:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh --feature metrics
```

The supported feature names are `metrics`, `debt`, `plugins`, and `pipeline`:

- `metrics` creates an isolated Swift source fixture, runs `swift-debt analyze`
  with JSON output, repeats the command with a different parser-job bound, and
  proves the reports are byte-for-byte identical.
- `debt` creates an isolated fixture, runs the real `swift-debt debt analyze`
  ranked workflow with a frozen Git reference time, and validates the native
  debt-report shape.
- `plugins` delegates to the repository's real
  `scripts/smoke-test.py --plugins` harness, which creates its own temporary
  SwiftPM consumer and exercises both the build and command plugins.
- `pipeline` creates a version-1 local configuration, runs `swift-debt pipeline run`,
  and proves that its passed report and per-check artifacts were retained.

For a direct manual drive, use stable command arguments rather than terminal
coordinates:

```sh
.build/debug/swift-debt analyze Examples/Sources \
  --format json --jobs 1 --output /tmp/swift-debt-report.json
.build/debug/swift-debt debt analyze Examples/Sources \
  --format debt-json --debt-reference-time 2026-09-12T00:00:00Z \
  --top 5 --output /tmp/swift-debt-ranked.json
```

Use `--interactive-debt` only from an actual TTY. Its stable user controls are
the documented quit and navigation keys in the terminal explorer; do not use a
non-TTY pipe as evidence for interactive behavior.

## Evidence

Every helper run creates a unique directory under
`.verification/evidence/run-<UTC timestamp>-<pid>/`. It preserves:

- the exact command lines and exit statuses;
- drive command transcripts;
- the generated JSON or plugin smoke evidence;
- deterministic comparison results and validation summaries.
- pipeline configuration, report receipt, and per-check artifacts.

Proof must exercise the executable or plugin the way a package user does. Do
not call internal Swift types, inject test-only setters, or rely on a test-only
endpoint. Capture both the action and resulting state. For reports, inspect the
written file and its decoded fields. For plugins, inspect the consumer build
result and the generated `SwiftDebt.analysis.swift` stamp. The plugin smoke
fixture is intentionally temporary and does not stand in for a production
package dependency.

The debt workflow uses a frozen reference time because Git-history evidence is
otherwise intentionally unavailable. Verify that the report says so when the
fixture is not a Git repository; do not treat missing history as zero risk.

## Cleanup

The helper removes only the fixture directory it created. Evidence remains at
`.verification/evidence/` after the process exits so it can be reviewed or
attached to a report. Do not kill processes by name. These workflows are
short-lived and the helper has no background process to terminate. If a manual
TTY drive is interrupted, close the exact shell or terminal session that was
started for it and leave unrelated Swift processes alone.

## Helpers

The executable helper is:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh \
  --feature metrics|debt|plugins|pipeline
```

The command defaults to the active Pi skill path. To verify a reviewed staged copy before promotion, set `SWIFTDEBT_VERIFY_ROOT` to that copy’s path; the helper discovers the repository by walking up to `Package.swift`.

It is Bash 3.2-compatible and requires the repository's Swift toolchain and
Python 3 for the plugin feature. `--doctor` is read-only and does not rebuild.
The feature map in `features/` is the maintained source for user-facing paths;
update it whenever CLI commands, output formats, or plugin behavior changes.

## Maintenance

When the CLI or plugin surface changes, update this skill and its feature map,
then execute one mapped feature end to end again. Use
`/maintain-verification-skill` for the maintenance loop when available.
