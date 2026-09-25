# SwiftDebt

A Swift CLI, reusable analysis library, SwiftPM command plugin, and incremental build-tool plugin based on **SCMA: A Lightweight Tool to Analyze Swift Projects**, by Fazle Rabbi, Syeda Sumbul Hossain, and Mir Mohammad Samsul Arefin.

<!-- swiftdebt-release-version:start -->
**Version:** 0.8.0.
<!-- swiftdebt-release-version:end -->

**Toolchain baseline:** Swift 6.2.x, Swift 6 language mode. The shipping manifest pins SwiftSyntax **602.0.0** and declares macOS 13, iOS and iPadOS 16, tvOS 16, watchOS 9, and visionOS 1 as its minimum Apple deployment targets. Linux validation used Swift 6.2.1. Newer Swift syntax is not implicitly supported by the pinned parser.

`SwiftDebtKit` also builds with Xcode 27.0 beta (27A5228h) against the iOS, tvOS, watchOS, and visionOS 27.0 simulator SDKs. The iOS simulator build covers both iPhone and iPadOS destinations.

The standalone Xcode build-plugin consumer is validated with Xcode 27.0 (27A5228h), Apple Swift 6.4 (swiftlang-6.4.0.27.1), and macOS 27.2 (26B5091g). The check uses the shipping package manifest unchanged.

This is an independent, paper-inspired implementation, **not a reproduction of the authors' tool**. All ten metric families are implemented, with documented measurement policies. Coupling and field access are syntactic estimates; duplicate detection is native Swift, not Lizard. The paper's inconsistent scoring formulas are opt-in rather than treated as a validated quality grade.

## Contents

- [Installation](#installation)
- [Tutorials and documentation](#tutorials-and-documentation)
- [Quick start](#quick-start)
- [Command plugin](#command-plugin)
- [Build plugin](#build-plugin)
- [Genesis code reviewer workflow](#genesis-code-reviewer-workflow)
- [Configuration](#configuration)
- [Library API](#library-api)
- [Architecture](#architecture)
- [Validation and limitations](#validation-and-limitations)

Detailed references: [paper mapping](docs/PAPER_MAPPING.md), [measurement definitions](docs/METRICS.md), [plugin integration](docs/PLUGINS.md), [release process](docs/RELEASE_PROCESS.md), [validation record](docs/VALIDATION.md).

## Installation

Add the released package and the products you need to your package manifest:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyTools",
    dependencies: [
        // swiftdebt-release-version:start
        .package(url: "https://github.com/brunogama/SwiftDebt.git", from: "0.8.0")
        // swiftdebt-release-version:end
    ],
    targets: [
        .executableTarget(
            name: "DebtTool",
            dependencies: [
                .product(name: "SwiftDebtKit", package: "SwiftDebt")
            ]
        ),
        .target(
            name: "AppCore",
            plugins: [
                .plugin(name: "SwiftDebtBuildPlugin", package: "SwiftDebt")
            ]
        ),
    ]
)
```

Depending on the package also exposes the `swift-debt` command plugin. The build plugin requires a `.swift-debt.json` file in the consuming package root; an empty `{}` is valid.

To install the standalone CLI from a tagged release:

```sh
# swiftdebt-release-version:start
git clone --branch v0.8.0 --depth 1 https://github.com/brunogama/SwiftDebt.git
# swiftdebt-release-version:end
cd SwiftDebt
swift build -c release
.build/release/swift-debt --version
.build/release/swift-debt analyze /path/to/project
```

## Tutorials and documentation

The [published Swift-DocC site](https://brunogama.github.io/SwiftDebt/documentation/swiftdebtkit/) includes these practical tutorials:

- [Use the standalone CLI](Sources/SwiftDebtKit/SwiftDebtKit.docc/Tutorials/StandaloneCLI.md)
- [Analyze source with the library API](Sources/SwiftDebtKit/SwiftDebtKit.docc/Tutorials/LibraryAPI.md)
- [Run the command plugin](Sources/SwiftDebtKit/SwiftDebtKit.docc/Tutorials/CommandPlugin.md)
- [Attach the build plugin](Sources/SwiftDebtKit/SwiftDebtKit.docc/Tutorials/BuildPlugin.md)
- [Enforce debt policy in CI](Sources/SwiftDebtKit/SwiftDebtKit.docc/Tutorials/CIEnforcement.md)

## Quick start

From the extracted package directory, using a Swift 6.2.x toolchain:

```sh
swift build
swift test
swift run swift-debt analyze Examples/Sources
swift run swift-debt analyze Examples/Sources --format json
swift run swift-debt analyze Examples/Sources --format html --output .swift-debt/report.html
```

The initial normal build resolves and compiles the pinned SwiftSyntax dependency. Once built, the analyzer itself does not need network access, the target application's dependencies, a Python server, or a successful target build. The included Python scripts are optional verification tools, not runtime dependencies.

Analyze your project, including non-class Swift types, with a bounded number of parsing jobs:

```sh
swift run swift-debt analyze /path/to/project \
  --type-scope nominals \
  --jobs 4 \
  --format json \
  --output .swift-debt/project.json
```

An explicit input directory becomes the configuration/discovery root. For example, `analyze /project/Sources` looks for `/project/Sources/.swift-debt.json`, not `/project/.swift-debt.json`; use `--config /project/.swift-debt.json` when needed. Output paths are relative to the current working directory, not the scanned root.

Supported SCMA-paper formats are `text`, `json`, `csv`, `html`, and `diagnostics`. HTML is standalone and script-free. JSON is the full machine-readable SCMA report; CSV is a flat observation export, not an equivalent serialization of the report. Ranked debt analysis can additionally render `debt-json`, `debt-markdown`, `debt-dot`, `debt-text`, `debt-compact`, `debtmap-json`, and `debt-dashboard` when `debtAnalysis` is configured. `debtmap-json` is a deterministic compatibility projection for Debtmap-oriented automation, not the native SwiftDebt debt model. `debt-dashboard` is a self-contained browser dashboard over the native debt-report schema. The closed conformance record supports `Debtmap 0.23.0 workflow/capability parity for Swift` for the frozen Swift workflow matrix. Canonical outputs are checked in as [golden fixtures](Tests/SwiftDebtKitTests/Fixtures/DebtReport), and release evidence is in [the Debtmap acceptance record](docs/debtmap/release-quality-acceptance.md).

Git-history recency in ranked debt analysis requires an explicit ISO-8601 reference time so repeated runs remain deterministic:

```sh
swift run swift-debt debt analyze /path/to/project \
  --format json \
  --debt-reference-time 2026-09-12T00:00:00Z
```

Without the CLI option or the `debtReferenceTime` configuration key, Git-history evidence is reported as unavailable. SwiftDebt does not substitute the Unix epoch or the ambient clock. Direct library callers can continue to inject `AnalysisRequest(debtReferenceTime:)` as a `Date`.

Enforce an explicit CI threshold policy:

```sh
swift run swift-debt analyze /path/to/project \
  --type-scope nominals \
  --threshold CCF=15 \
  --threshold NOPF=6 \
  --fail-on-violation \
  --format diagnostics
```

The values 15 and 6 above are **example policy choices**, not thresholds from the paper. Findings use strict `value > threshold`. By default, findings do not fail the process; parse/configuration/input errors do.

CLI exit statuses: `0` complete analysis with no opted-in gate failure; `1` complete analysis that violates an enabled gate; `2` invalid input/configuration, incomplete analysis, or a resource-limit failure. By default a file with parse errors is skipped with a warning and the analysis stays complete; `--strict` (or `"strictSyntax": true`) turns any parse error into an incomplete analysis and exit status 2. A type declared in mutually exclusive `#if` branches is omitted with a warning, never an error. SwiftPM wraps plugin failures and may report its own nonzero status rather than preserving these exact numbers.

Scoring modes:

```sh
swift run swift-debt analyze Examples/Sources --scoring none     # default: raw metrics
swift run swift-debt analyze Examples/Sources --scoring paper    # literal Table I formulas
swift run swift-debt analyze Examples/Sources --scoring bounded  # formulas, then explicit clamp
swift run swift-debt analyze Examples/Sources --scoring corrected  # bounded, plus DC ratio = duplicated / total lines
```

`paper` can produce results greater than 5. Undefined scores are `null` in JSON, never replaced with a passing grade. The overall average is absent/null unless analysis is complete and all ten individual scores are defined. `bounded` is a convenience transform, not a scientifically corrected scoring model. `corrected` additionally replaces the paper's printed DC ratio (`duplicatedLines * totalLines / totalParams`, which zeroes the score on any clone) with `duplicatedLines / totalLines`; every other equation is unchanged.

## Command plugin

After adding the released dependency shown in [Installation](#installation), run the command from the consumer package:

```sh
swift package swift-debt --format json
swift package swift-debt --target AppCore --target Domain --format json
swift package swift-debt --include-tests --type-scope nominals
```

The command plugin uses SwiftPM's exact target source lists and module names. By default it analyzes regular Swift targets in the current package, excluding test targets and dependency packages. An explicit `--target` may select a test target. There is no need to attach the command plugin to every target.

The plugin requests no package-write or network permissions. For a report written outside the plugin work directory, grant only the intended output directory:

```sh
mkdir -p reports
swift package --allow-writing-to-directory ./reports swift-debt \
  --format html --output ./reports/swift-debt.html
```

Alternatively, redirect stdout from the shell. Keep machine output and SwiftPM's build messages separate; the analyzer's own JSON renderer is deterministic, while launcher logging is controlled by SwiftPM.

## Build plugin

Attach `SwiftDebtBuildPlugin` to each target you want checked:

```swift
.target(
    name: "AppCore",
    plugins: [
        .plugin(name: "SwiftDebtBuildPlugin", package: "SwiftDebt")
    ]
)
```

**Create `.swift-debt.json` in the consuming package root before the first build.** An empty `{}` is valid. Requiring an existing file makes configuration changes an explicit build input instead of relying on discovery of a previously nonexistent file.

```json
{
  "typeScope": "nominals",
  "scoring": "none",
  "thresholds": { "CCF": 15, "NOPF": 6 },
  "failOnViolation": true
}
```

```sh
swift build
```

The plugin emits source-located diagnostics. It uses a regular `buildCommand` with declared source/configuration inputs and a comment-only generated `SwiftDebt.analysis.swift` completion file. No report or source text is bundled into your application as a generated resource. The completion file adds no runtime declarations. A no-op build can skip analysis once inputs/tool outputs are stable.

Build checks are **per target**; they cannot calculate project-wide coupling or cross-target duplicates. Use the command plugin for an aggregate package report. Do not attach the build plugin to a target whose Swift files are all excluded by configuration; empty selected input is an error, not a clean result.

A complete consumer example is provided:

```sh
cd Examples/PluginConsumer
swift build
swift package swift-debt --target Demo --type-scope nominals --format json
```

The build plugin supports Swift package targets, including packages opened in Xcode, and standalone Xcode project targets through its `XcodeBuildToolPlugin` adapter. The checked-in [Xcode consumer project](Examples/XcodePluginConsumer) attaches the plugin to a macOS framework target. Run `python3 scripts/xcode-plugin-smoke.py` on the pinned Xcode environment to verify a clean build, warmed no-op, source and configuration invalidation, an enforced failure, and recovery.

---

## Genesis code reviewer workflow

This repository includes [`.github/workflows/genesis-code-reviewer.yml`](.github/workflows/genesis-code-reviewer.yml), a manual GitHub Actions workflow for reviewing production Genesis code with the workflow's current SwiftDebt commit.

The workflow:

- checks out the current repository and commit as `SwiftDebt`;
- configures a strict SSH identity for the `genesis-production` host alias;
- clones the Genesis repository over SSH, defaulting to `git@genesis-production:brunogama/Genesis.git` and the `production` ref;
- runs `swift-debt analyze` against the selected Genesis path, defaulting to `Sources`;
- uploads `genesis-swift-debt-diagnostics` as an artifact.

Configure these repository secrets before running it:

| Secret | Purpose |
| --- | --- |
| `GENESIS_SSH_PRIVATE_KEY` | Read-only deploy key for the Genesis repository. |
| `GENESIS_SSH_KNOWN_HOSTS` | Trusted `known_hosts` entries for the SSH host. Do not replace this with disabled host checking. |

Optional dispatch inputs let you override the SSH repository URL, reviewed ref, analyzed path, and whether configured SwiftDebt threshold violations fail the workflow.

---

## Configuration

The CLI and command plugin automatically load `.swift-debt.json` at the analysis root when it exists. The build plugin requires that file. Unknown keys, unknown metrics, invalid enums, and out-of-range numeric options are errors rather than silently ignored configuration.

```json
{
  "typeScope": "classes",
  "scoring": "none",
  "format": "text",
  "debtReferenceTime": "2026-09-12T00:00:00Z",
  "thresholds": {
    "LOCC": 500,
    "WMCC": 200,
    "CCF": 20,
    "NOPF": 10,
    "DC": 10
  },
  "exclude": ["Generated", "Vendor"],
  "jobs": 4,
  "failOnViolation": false,
  "strictSyntax": false,
  "minimumDuplicateLines": 11,
  "maximumDuplicateComparisons": 250000,
  "maximumFileBytes": 16777216
}
```

These five thresholds reproduce the thresholds actually specified by Table I. The other five metrics remain informational unless explicitly configured. `NOAV` has an unresolved desirability direction in the paper; any custom NOAV upper-bound gate is your own policy, not its recommendation.

CLI scalar options override file settings. CLI thresholds merge by metric, and exclusions append to file exclusions. `--fail-on-violation` can enable a gate; it does not disable a gate already enabled in the configuration. `--strict` likewise enables `strictSyntax` but cannot disable it. JSON metric keys are case-sensitive uppercase IDs; CLI threshold IDs are normalized to uppercase.

`debtReferenceTime` must be an ISO-8601 internet timestamp with a time zone, such as `2026-09-12T00:00:00Z`. `--debt-reference-time` overrides the configured value.

Exclusions are literal root-relative path prefixes such as `Generated` or `Sources/Legacy`, not globs. Directory scanning always omits `.git`, `.build`, `.swiftpm`, `.swift-debt`, `Pods`, `Carthage`, `node_modules`, symbolic links, and discovered `Package.swift` files. An explicitly selected `Package.swift` can still be analyzed. A filesystem scan treats all input as one virtual `Workspace` module; prefer the command plugin for a multi-module Swift package.

Parsing jobs must be `1...64`; the default is the active processor count, capped at 8. The per-file size ceiling defaults to 16 MiB and can be overridden with `--max-file-bytes`. The clone comparison budget is a deterministic work limit, **not a time or total-memory limit**. Exhausting it fails the analysis rather than falsely reporting no duplication. There is no persistent content cache; files are parsed again on each CLI invocation. SwiftPM handles build-level invalidation.

The default clone floor is 11 nonblank code lines, corresponding to the paper's `>10` condition. A custom lower DC threshold also requires a matching `minimumDuplicateLines` in the JSON configuration. The floor must not exceed the configured DC threshold plus one. Custom floors require `scoring: "none"`; paper/bounded/corrected modes retain floor 11 for consistency with the selected compatibility policy.

## Library API

Add the `SwiftDebtKit` product to your tool target. The product exposes `SwiftDebtKit` and `SwiftDebtCore` modules:

```swift
import SwiftDebtCore
import SwiftDebtKit

func inspect() async throws -> AnalysisReport {
    let source = SourceUnit(
        path: "Sources/Feature/Example.swift",
        module: "Feature",
        content: """
        final class Example {
            func answer(_ value: Int) -> Int {
                if value > 0 { return value }
                return 0
            }
        }
        """
    )
    return try await Analyzer().analyze(
        [source],
        options: AnalysisOptions(typeScope: .nominals),
        jobs: 2
    )
}
```

`Analyzer` is the in-memory boundary. `AnalysisService().run(AnalysisRequest(...))` is the filesystem/configuration/reporting boundary shared by the CLI and plugins. Inputs and report values are `Sendable`; parsing uses bounded task-group concurrency. No DI container or global service locator is involved.

## Architecture

```text
SwiftPM plugins / CLI -> swift-debt executable -> SwiftDebtKit composition root
                                                |       |       |
                                                v       v       v
                                           SwiftDebtSyntax   |  SwiftDebtReporting
                                                |       |       |
                                                +-------v-------+
                                                    SwiftDebtCore
```

| Target | Responsibility |
| --- | --- |
| `SwiftDebtCore` | Domain values, ten metrics, paper equations, coupling aggregation, clone engine. **No imports.** |
| `SwiftDebtSyntax` | SwiftParser/SwiftSyntax extraction and parser diagnostics; no filesystem access. |
| `SwiftDebtReporting` | Text, JSON, CSV, HTML, diagnostic serialization. |
| `SwiftDebtKit` | Discovery, input validation, configuration, bounded orchestration, safe report writes. |
| `swift-debt` | Strict argument parsing, stdout/stderr, process exit statuses. |
| `SwiftDebtCommandPlugin` | Source/module manifest and on-demand package analysis. |
| `SwiftDebtBuildPlugin` | Per-target build commands and explicit input/output tracking. |

Implementation-only types use internal/package access. Public types form the reusable domain/application boundary. Dependency versions are pinned in the manifest; the shipping package contains no host-library search paths or unsafe compiler flags.

## Validation and limitations

The [macOS release validation](https://github.com/brunogama/SwiftDebt/actions/runs/35983890308) resolved the pinned SwiftSyntax 602.0.0 dependency with Swift 6.2, passed 186 Swift Testing tests, and passed 28 CLI and SwiftPM plugin subprocess checks. The plugin checks exercise a real downstream package. The earlier Linux validation used a disposable offline dependency copy; its scope and qualifications remain in [the validation record](docs/VALIDATION.md).

An independent Xcode 27.0 run resolved the shipping manifest normally and passed the standalone project plugin smoke suite on macOS 27.2. The environments, commands, and qualifications are in [docs/VALIDATION.md](docs/VALIDATION.md).

Run full validation on your own toolchain:

```sh
./scripts/verify.sh
```

This tool does not type-check or expand macros, perform compiler-backed name binding, evaluate `#if`, model dispatch, prove architecture compliance, or validate the paper's quality score against outcomes. Debtmap parsers for non-Swift languages are outside the current SwiftDebt parity target. The current performance gate uses frozen examples, so it does not establish large-repository behavior. Original SCMA/Lizard parity has not been established. [The limitations plan](docs/LIMITATIONS_PLAN.md) states the evidence required to close each gap. Read [METRICS.md](docs/METRICS.md) before comparing results with another analyzer.
