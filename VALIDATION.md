# Validation record

## Environment and scope

Validation host: x86_64 Linux, `Swift version 6.2.1 (swift-6.2.1-RELEASE)`, target `x86_64-unknown-linux-gnu`.

The container's build process could not resolve `github.com`. An ordinary dependency fetch/build of SwiftSyntax 602.0.0 was therefore **not completed**. The installed Swift 6.2.1 toolchain already included host `SwiftSyntax`, `SwiftParser`, and `SwiftParserDiagnostics` modules/libraries. Tests used them through a **disposable validation copy**, not by adding private search paths or unsafe flags to the shipping package.

The distributed `Package.swift` uses the ordinary exact remote SwiftSyntax 602.0.0 dependency. `swift package dump-package` validated that manifest. Resolving/compiling that exact external source release is a remaining verification step on a network-enabled machine.

## Executed checks

| Check | Result | Qualification |
| --- | --- | --- |
| Shipping `swift package dump-package` | Passed | Manifest structure only; not remote dependency resolution. |
| SwiftPM compilation of core/parser/reporting/kit/CLI | Passed | Swift 6 language mode, installed host parser libraries. |
| Swift Testing | **51 tests in four suites passed** | Includes parameterized complexity cases and a finite exhaustive clone check. |
| CLI and plugin subprocess suite | **27 checks passed** | Real executable and downstream SwiftPM consumer, using the offline dependency copy. |
| macOS build and sandbox | Not run | Linux host. |
| Conditional Xcode project adapter | Not compiled/run | `XcodeProjectPlugin` is unavailable on this host. |
| Original SCMA/Lizard parity | Not established | Original implementation/data not supplied; measurement policies differ explicitly. |
| Large-repository performance/recall study | Not performed | No latency, memory, accuracy, or scalability benchmark claim. |

Raw final test output is in [validation-logs/swift-test.log](validation-logs/swift-test.log). The integration summary is in [validation-logs/smoke-test.log](validation-logs/smoke-test.log). The XCTest discovery wrapper can display zero XCTest cases before Swift Testing runs; the final Swift Testing line records the 51 actual tests.

## What the tests cover

The core suite checks Table I equations, unbounded/clamped behavior, missing/undefined scores, clone hashes verified against signatures, same-file nonoverlap, duplicate line unions, and work-budget failure. A finite exhaustive check compares the detector with a brute-force duplicated-line union for all binary line sequences of lengths 2 through 9 at floor 2. This caught a real overlapping-periodic-span bug during implementation; the delivered code uses only verified diagonal coverage to skip seed windows.

The syntax suite covers supported decision nodes (including unfolded ternaries), comments versus literals, nested block comments, multiline strings, Unicode/CRLF locations, parameter/property extraction, nested callable independence, explicit self and shadowing, globals versus locals, initializers/deinitializers, imports, and malformed source.

The whole-source suite checks all ten summaries, class/nominal scope, cross-file extensions, module identity and import ambiguity, undirected coupling, conservative field use, syntax failures and conditional declaration conflicts, literal score/gate separation, all-ten averaging, output ordering under concurrency, and HTML/CSV text safety.

The filesystem suite covers exclusions, configuration validation, empty input, invalid UTF-8, manifest escape rejection, output protection, report writes, gate statuses, and marker creation only after successful analysis.

The subprocess suite tests CLI help/version, strict bad arguments, job ranges, deterministic JSON, thresholds, all output formats, malformed source, output protection, the missing-build-config requirement, a downstream build-plugin invocation, warmed no-op behavior, source invalidation, configuration invalidation, gate failure/recovery, command-plugin target selection, and invalid plugin target arguments.

These are focused automated checks, not a complete proof of parser accuracy, compiler semantics, security isolation, or equivalence on every Swift program.

## Reproduce the normal build

Use a Swift 6.2.x toolchain with access to resolve the pinned package:

```sh
swift package dump-package
swift build
swift test
python3 scripts/smoke-test.py --binary .build/debug/scma --plugins
```

Or run `./scripts/verify.sh`, which performs the manifest/build/tests/integration checks and validates that SCMACore has no imports. Python 3.10+ is only needed for the optional subprocess verification scripts. The smoke suite allows 900 seconds per subprocess by default; override with `--timeout SECONDS` for a slower cold SwiftSyntax build.

For style validation, run the toolchain's formatter separately:

```sh
swift format lint --strict --recursive Sources Tests Plugins Package.swift Examples
```
