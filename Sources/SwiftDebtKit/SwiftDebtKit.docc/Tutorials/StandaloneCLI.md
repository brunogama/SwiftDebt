# Analyze a Project with the Standalone CLI

Build a tagged SwiftDebt release, analyze a directory, and interpret the process result.

## Build the released executable

Clone the tagged source so the executable and its documentation describe the same release:

```sh
# swiftdebt-release-version:start
git clone --branch v0.5.0 --depth 1 https://github.com/brunogama/SwiftDebt.git
# swiftdebt-release-version:end
cd SwiftDebt
swift build -c release
.build/release/swift-debt --version
```

The first build resolves the pinned SwiftSyntax dependency. The executable does not require a server or the analyzed project's dependencies after it is built.

## Analyze source

Run the analyzer with a bounded parser job count and write a deterministic JSON report:

```sh
.build/release/swift-debt analyze /path/to/project \
  --type-scope nominals \
  --jobs 4 \
  --format json \
  --output swift-debt.json
```

Use `text`, `json`, `csv`, `html`, or `diagnostics` for metric reports. Add a `.swift-debt.json` file at the analysis root, or pass `--config`, when you need repeatable exclusions, thresholds, or scoring settings.

---

## Review syntax rule observations

Text is the default format when configuration does not override it. Pass `--format text` to select it explicitly and append the built-in syntax rule catalog:

```sh
.build/release/swift-debt analyze /path/to/project --format text
```

The catalog reports these deterministic source observations:

| Rule identity | Severity | Observation |
| --- | --- | --- |
| `swiftdebt.force-try` | Warning | A `try!` expression, located at `!`. |
| `swiftdebt.concurrency.unchecked-sendable` | Information | An `@unchecked Sendable` conformance spelling, located at `@`. |
| `swiftdebt.concurrency.actor-nonisolated-unsafe` | Information | A direct actor member declared `nonisolated(unsafe)`, located at `unsafe`. |
| `swiftdebt.code-smell.force-cast` | Warning | An `as!` expression, located at `!`. |
| `swiftdebt.code-smell.empty-catch` | Warning | A catch clause with no code block items, located at `catch`. |

The concurrency observations identify assumptions that deserve review. They do not prove a data race or a defect. [`@unchecked Sendable`](https://developer.apple.com/documentation/swift/sendable) disables compiler enforcement for that conformance, while [`nonisolated(unsafe)`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0412-strict-concurrency-for-global-variables.md) opts a declaration out of static isolation checking. The actor rule examines direct members in actor declarations and makes no ownership claim for actor extensions.

All conditional-compilation branches are inspected because syntax-only analysis does not evaluate `#if` conditions. JSON and the other non-text formats retain their existing schema and do not include rule observations.

---

## Interpret completion

The executable exits with status `0` after a complete analysis, status `1` when an opted-in policy gate finds a violation, and status `2` for invalid input, invalid configuration, or incomplete analysis. A parse error is a warning in metric reports by default; pass `--strict` to make that report incomplete. Default text rule analysis also exits with status `2` when any selected rule cannot execute for a source, including a parse failure, because only a committed rule execution can establish absence.
