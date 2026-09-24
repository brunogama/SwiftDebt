# Plan to close validation and analyzer gaps

SwiftDebt currently reports deterministic syntax evidence. The plan below adds stronger evidence without changing the meaning of existing reports. A result must state which analysis mode and build configuration produced it. A syntax estimate must never be presented as a compiler-verified fact.

## Definition of done

Each row is closed only when its acceptance check runs on the shipping package, its evidence is linked from [the validation record](VALIDATION.md), and the public limitation statement is updated. A passing build alone does not close a semantic or empirical claim. If a source implementation or ground-truth dataset cannot be obtained, the corresponding claim remains unverified.

| Gap | Current evidence | Required acceptance evidence |
| --- | --- | --- |
| Pinned dependency and macOS SwiftPM plugins | The [2026-09-24 release run](https://github.com/brunogama/SwiftDebt/actions/runs/35983890308) resolved SwiftSyntax 602.0.0, passed 186 tests and 28 subprocess checks, and ran both plugins in a downstream package. | Keep the real dependency build and downstream plugin checks in CI. Treat a failed or skipped check as an open validation gap. |
| Xcode project adapter | The [hosted Xcode 27 job](https://github.com/brunogama/SwiftDebt/actions/runs/36006238964/job/107655000593) passed the standalone consumer smoke gate, including plugin sandbox behavior, source and configuration invalidation, an enforced gate failure, and recovery. | Keep the Xcode consumer smoke gate in CI. Treat a failed or skipped check as an open validation gap. |
| Type checking, macros, and `#if` | The parser observes source text without a compiler invocation. | [Issue #32](https://github.com/brunogama/SwiftDebt/issues/32) defines compiler evidence. [Issue #33](https://github.com/brunogama/SwiftDebt/issues/33) checks active configurations and macro expansion. Unavailable evidence stays explicit. |
| Name binding and dispatch | Type and call edges use documented syntax heuristics. | [Issue #34](https://github.com/brunogama/SwiftDebt/issues/34) compares compiler-resolved symbols with overload, alias, generic, import, inheritance, protocol, and dynamic-dispatch fixtures. |
| Architecture compliance | Reports describe dependencies but do not evaluate architecture rules. | [Issue #35](https://github.com/brunogama/SwiftDebt/issues/35) defines versioned rules and tests proven, unknown, and condition-dependent edges in a downstream package. |
| Paper quality score | The paper equations are implemented, but predictive validity is unknown. | [Issue #36](https://github.com/brunogama/SwiftDebt/issues/36) uses independently recorded outcomes, held-out evaluation, uncertainty, and simple baselines. |
| Large-repository behavior | CI times frozen small examples against a comparable SwiftDebt reference. | [Issue #37](https://github.com/brunogama/SwiftDebt/issues/37) requires three pinned repositories with at least 100,000 Swift code lines each, including one with at least 500,000. It records ten cold and ten warm runs per repository, plus independently sampled finding review. |
| Original SCMA and Lizard parity | Policies differ and no original reference corpus is checked in. | [Issue #38](https://github.com/brunogama/SwiftDebt/issues/38) obtains a legal reference and records metric-by-metric differences. Without those inputs, parity stays unverified. |
| Non-Swift Debtmap parsers | SwiftDebt's current target is Swift. | [Issue #39](https://github.com/brunogama/SwiftDebt/issues/39) starts with Python 3 and a frozen Debtmap 0.23.0 reference workflow. The gap stays open until the full upstream language inventory is recorded and every parser has equivalent evidence or an explicit unverified status. |

---

## Delivery order

1. Keep the real-package validation record current and retain CI coverage for both SwiftPM and Xcode plugin hosts.
2. Establish a compiler evidence contract before changing metric calculations. Compare syntax and compiler-backed results on fixed fixtures, then add configuration-aware parsing, macro expansion, binding, and dispatch as separate changes.
3. Build architecture rules on the resolved dependency evidence. Reject only violations that the chosen mode can prove.
4. Freeze the empirical inputs before making performance or score claims. Measure large repositories and outcome validity independently.
5. Assess original SCMA/Lizard parity and non-Swift support as separate compatibility projects. Inventory all Debtmap 0.23.0 languages before adding follow-on parser issues. Publish a claim only when the corresponding reference data and executable checks exist.

Each change must retain the existing deterministic syntax mode and report schema unless a versioned migration is documented. [Issue #30](https://github.com/brunogama/SwiftDebt/issues/30) tracks the complete sequence and its blocking edges. The [measurement specification](METRICS.md) remains the reference for what current reports mean.

The [decision record](limitations-decisions.tsv) records why the current validation gap was closed and why the remaining work is separate.
