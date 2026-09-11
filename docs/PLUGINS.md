# Plugin integration

## Distinct responsibilities

`SCMACommandPlugin` runs an on-demand report across selected Swift targets in the root package. `SCMABuildPlugin` attaches diagnostics to an individual target's build graph. Both call the same `scma` executable and metric engine; neither implements a second set of metrics.

The command plugin is not a Source Editor Extension or a compiler macro. The build plugin is an opt-in SwiftPM build tool, with a conditional Xcode project adapter. There is no dynamically loaded third-party rule/plugin API.

## Complete local SwiftPM example

Given sibling directories `YourPackage/` and `SwiftSCMA/`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "YourPackage",
    products: [
        .library(name: "Feature", targets: ["Feature"])
    ],
    dependencies: [
        .package(name: "SwiftSCMA", path: "../SwiftSCMA")
    ],
    targets: [
        .target(
            name: "Feature",
            plugins: [
                .plugin(name: "SCMABuildPlugin", package: "SwiftSCMA")
            ]
        )
    ]
)
```

Create `YourPackage/.scma.json` before invoking the build:

```json
{
  "typeScope": "nominals",
  "scoring": "none",
  "thresholds": { "CCF": 15 },
  "failOnViolation": false
}
```

The CCF value above is an example repository policy, not the paper's original limit of 20. An empty JSON object also works and uses defaults. Turn `failOnViolation` on only when you intend findings to fail builds. Configuration and input errors fail regardless of this setting. A file the pinned parser cannot parse is skipped with a warning rather than failing the build, unless `"strictSyntax": true` is set.

```sh
cd YourPackage
swift build
swift package scma --target Feature --type-scope nominals --format json
```

The command plugin does not need a `.plugin(...)` entry on a consumer target. Depending on the package exposes its custom `scma` command. The target attachment is only for build-time checks.

## Command selection and permissions

Repeat `--target NAME` to select several targets. With no target flags, regular Swift targets are selected; test targets require `--include-tests`. An explicitly named test target is permitted without that flag. Dependencies outside the current root package are not automatically analyzed. Unknown or missing target values fail. Remaining CLI options are forwarded using argument arrays, not shell interpolation.

The plugin uses `PackagePlugin.ArgumentExtractor`. It reserves `--manifest` and `--stamp` for its own source selection/output tracking. Do not pass a positional scan path to the command plugin: it has already selected input from the package model. Use the standalone CLI for arbitrary directories or custom JSON source manifests.

The plugin writes an exact-source JSON manifest to its work directory and only rewrites that manifest when its contents change. It requests neither network access nor package-directory write access. Normal SwiftPM dependency resolution/building happens outside the analyzer's own runtime and may require the network on first use.

For report files in the consumer package, explicitly grant the narrow directory:

```sh
mkdir -p reports
swift package --allow-writing-to-directory ./reports scma \
  --format html --output ./reports/scma.html
```

The broader `--allow-writing-to-package-directory` flag is not required by this design. The macOS sandbox behavior of these invocations was not tested here; the integration test ran on Linux. A user's own shell can redirect stdout without requiring the plugin to write that destination.

## Build graph and configuration

Each invocation's manifest contains only the target's Swift sources. A build command declares those sources, the manifest, and the root `.scma.json` as inputs. Parsing uses the configured `jobs` value, which defaults to the active processor count capped at 8. Its output is the plugin-work-directory `SCMA.analysis.swift`, containing only a generated comment and no declarations.

The configuration file is mandatory for the build plugin because a file that did not exist when the build graph was created would otherwise not be a reliable declared input. Creating optional configuration later was tested and shown to leave the prior analysis cached in the validation environment. Requiring an initial `{}` avoids that silent configuration-change failure mode. Deleting it is a configuration error.

The build command forces diagnostic format. It uses configuration for scope, limits, exclusions, parse concurrency, and gate policy. It does not accept command-plugin `--target` arguments. Source or existing configuration changes invalidate the analysis; unchanged inputs can reuse the generated output. Tool changes may legitimately invalidate the command. The offline validation's first follow-up build could relink host/destination tool variants, so its no-op assertion is made after one additional warm-up build.

A report file is not declared as a generated build output: SwiftPM can treat non-Swift generated output as a resource. Using a comment-only Swift completion file avoids shipping private analysis reports/resources in the consumer product. Successful analyses write the completion file, and failed analyses do not write it. A previously successful completion file is not deleted on failure; the command's nonzero exit status still fails the build and the newer inputs remain dirty.

The marker is specifically named and protected against replacing an unrelated existing Swift file. Plugin manifests live in plugin work directories; source files are never rewritten. The plugin excludes its own completion marker from later source selection.

An empty target before selection produces no build commands. A target with source files that are all subsequently excluded by analysis configuration fails with “No Swift source files were selected.” Avoid attaching the plugin to an intentionally entirely excluded target.

## Project-wide versus target-local measurements

Build checks are target-local. For example, a class in target A referencing a class defined only in target B will not create a resolved cross-target coupling edge in A's build report. Duplicate code shared across A and B is likewise outside a target-local invocation's scope. Running the command plugin with both targets supplies the source/module mapping needed for the syntactic graph and clone detector to see both.

Neither route obtains type-checker bindings or guarantees that all generated sources are available at plugin planning time. The build plugin's source set is whatever SwiftPM/Xcode supplies to that plugin invocation. Do not assume it includes macro expansions or outputs of every other plugin.

## Xcode project adapter - unverified

`SCMABuildPlugin/plugin.swift` contains `#if canImport(XcodeProjectPlugin)` conformance to `XcodeBuildToolPlugin`. It translates Xcode's project root, target source inputs, plugin work directory, target display name, and resolved tool into the shared command builder. The adapter retains Path-based Xcode host APIs while the SwiftPM path uses URL APIs.

This branch cannot be compiled in the Linux environment used for delivery. Treat it as an implementation requiring verification on your exact Xcode version, not as tested IDE support. Its configuration is expected at the Xcode project directory, rather than a nested package's root, and source entries must remain within that root. Projects referencing source files outside their root will be rejected by the manifest containment check.

For a release on macOS, verify the adapter compiles, source locations appear correctly in the issue navigator, `.scma.json` changes rerun the tool, failure gates stop a build, a warmed no-op skips analysis, and no report resources appear in the product. This package's Linux results do not establish those properties for Xcode.

## Explicit source manifests for the standalone CLI

Advanced integrations can avoid directory inference:

```json
{
  "root": "/absolute/path/to/workspace",
  "sources": [
    { "path": "/absolute/path/to/workspace/Sources/Domain/Model.swift", "module": "Domain" },
    { "path": "/absolute/path/to/workspace/Sources/Feature/Service.swift", "module": "Feature" }
  ]
}
```

```sh
scma analyze --manifest /path/to/inputs.json --format json
```

Paths may be absolute or relative to manifest `root`. They must resolve to regular UTF-8 Swift files inside root; duplicate source paths, invalid/missing modules, escaping symlinks, and unreadable entries fail. The manifest is an input, not an output destination. Directory-only automatic exclusions do not override an explicit manifest; configured relative exclusions still apply.
