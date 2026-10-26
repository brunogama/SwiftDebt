# Verification pipeline

## Sub-features

- Render a policy-derived pipeline plan from a JSON configuration.
- Run explicitly bound local checks with per-check stdout and stderr artifacts.
- Preserve the configuration and a canonical `report.json` receipt in a new artifacts directory.
- Reject missing or reused artifact directories before launching commands.

## How to get to it (user POV)

Create a version-1 pipeline configuration containing the context and absolute
command bindings, then run the pipeline with a new artifacts directory:

```sh
.build/debug/swift-debt pipeline run pipeline.json --artifacts pipeline-artifacts
```

The configuration must identify its `risk`, `trigger`, and `impact`, and every
command binds a named pipeline check to an absolute executable and literal
arguments. `--artifacts` must name a directory that does not already exist.

## Driving it with the SwiftDebt CLI helper

Run:

```sh
${SWIFTDEBT_VERIFY_ROOT:-.pi/skills/verify-swift-debt}/scripts/verify.sh --feature pipeline
```

The helper writes a version-1 low-risk pull-request configuration with six
passing `/bin/sh` commands, runs the real `swift-debt pipeline run` path, and
validates the passed report plus the configuration, plan, and per-check result and log files
under the retained evidence directory.

## Gotchas

- The runner does not expand shell syntax; command executables are absolute and
  arguments are literal.
- A pipeline report records execution evidence; it does not authenticate a
  command's assertion or prove a finding was fixed.
- Reusing an artifacts directory is an input error that leaves its existing
  contents unchanged.
